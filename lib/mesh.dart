import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'db.dart';
import 'models.dart';
import 'security.dart';

const kService = 'com.schoolconnect.offline';
const kAdminId = 'ADMIN';

enum PeerState { found, connecting, verifying, connected }

class Peer {
  Peer(this.endpointId);
  final String endpointId;
  String teacherId = '';
  String name = '';
  bool valid = true;
  bool advAdmin = false; // advertises "enrollment open"
  bool adm = false; // peer is the admin device (from verified hello)
  int rv = 0;
  PeerState state = PeerState.found;
  DateTime foundAt = DateTime.now();
  DateTime stateAt = DateTime.now();
  String nonce = '';
  bool gotHello = false, gotProof = false;
  int regTries = 0;
  bool get authed => state == PeerState.connected;
}

/// Everything about identity, peer-to-peer networking, protocol and storage
/// glue lives here. UI listens to this ChangeNotifier.
class Mesh extends ChangeNotifier {
  Mesh._();
  static final Mesh i = Mesh._();

  // ---- identity / settings ----
  String? myId, myName;
  String school = '', key = '';
  int rosterVer = 0;
  bool isAdminDevice = false, enrollment = false;
  bool largeText = false, visible = true;
  List<Map<String, Object?>> roster = [];
  Set<String> _ids = {};
  late Directory docs, mediaDir;
  late File logoFile;
  Uint8List? logoBytes;

  // ---- runtime ----
  final Map<String, Peer> peers = {};
  bool running = false, _starting = false;
  String? error;
  String? openChat;
  String regStatus = '';
  String? removedNotice;
  final Map<String, double> progress = {};
  Timer? _timer;
  final Map<String, Timer> _authTimers = {};
  final Map<int, Payload> _filePayloads = {};
  final Map<int, Map<String, dynamic>> _fileMeta = {};
  final Map<int, PayloadStatus> _xfer = {};
  final Map<int, String> _outPids = {}; // payloadId -> mid (outgoing)
  final Map<int, String> _inPids = {}; // payloadId -> mid (incoming)
  // registration
  Completer<String?>? _reg;
  String? _regId, _regCode;
  Completer<void>? _logoDone;
  bool _logoExpected = false;

  bool get loggedIn => myId != null;
  String? get netId => myId ?? (isAdminDevice ? kAdminId : null);
  String get netName => myName ?? 'School Office';

  void bump() => notifyListeners();

  Future<void> loadIdentity() async {
    final d = Db.i;
    school = await d.kv('school') ?? '';
    key = await d.kv('key') ?? '';
    rosterVer = int.tryParse(await d.kv('rver') ?? '0') ?? 0;
    isAdminDevice = (await d.kv('is_admin')) == '1';
    myId = await d.kv('my_id');
    myName = await d.kv('my_name');
    largeText = (await d.kv('large')) == '1';
    visible = (await d.kv('visible')) != '0';
    docs = await getApplicationDocumentsDirectory();
    mediaDir = Directory(p.join(docs.path, 'SchoolConnect'));
    if (!await mediaDir.exists()) await mediaDir.create(recursive: true);
    logoFile = File(p.join(docs.path, 'school_logo.img'));
    if (await logoFile.exists()) logoBytes = await logoFile.readAsBytes();
    await reloadRoster();
  }

  Future<void> reloadRoster() async {
    roster = await Db.i.roster();
    _ids = roster.map((e) => e['id'] as String).toSet();
  }

  bool isMember(String id) => id == kAdminId || _ids.contains(id);

  String nameOf(String id) {
    if (id == kAdminId) return 'School Office';
    for (final r in roster) {
      if (r['id'] == id) return r['name'] as String;
    }
    return id;
  }

  Future<void> setLarge(bool v) async {
    largeText = v;
    await Db.i.setKv('large', v ? '1' : '0');
    bump();
  }

  Future<void> setVisible(bool v) async {
    visible = v;
    await Db.i.setKv('visible', v ? '1' : '0');
    if (v) {
      await start();
    } else {
      await stop();
    }
  }

  // ======================= Accounts =======================

  Future<String?> login(String id, String code) async {
    id = id.trim().toUpperCase();
    if (id.isEmpty || code.isEmpty) {
      return 'Please type your Teacher ID and access code.';
    }
    final t = await Db.i.teacher(id);
    if (t == null || t['verifier'] == null) {
      return 'This phone does not know that Teacher ID yet. Tap “Register this phone” first.';
    }
    if (!Sec.eq(Sec.hashSecret(t['salt'] as String, code),
        t['verifier'] as String)) {
      return 'Wrong Teacher ID or access code. Please try again.';
    }
    myId = id;
    myName = t['name'] as String;
    await Db.i.setKv('my_id', id);
    await Db.i.setKv('my_name', myName!);
    bump();
    start();
    return null;
  }

  Future<void> logout() async {
    await stop();
    myId = null;
    myName = null;
    await Db.i.delKv('my_id');
    await Db.i.delKv('my_name');
    bump();
  }

  Future<void> adminSetup(String schoolName, String pin) async {
    final salt = Sec.randomB64(12);
    await Db.i.setKv('school', schoolName.trim());
    await Db.i.setKv('key', Sec.randomB64(32));
    await Db.i.setKv('is_admin', '1');
    await Db.i.setKv('admin_salt', salt);
    await Db.i.setKv('admin_hash', Sec.hashSecret(salt, pin));
    await Db.i.setKv('rver', '1');
    school = schoolName.trim();
    key = (await Db.i.kv('key'))!;
    rosterVer = 1;
    isAdminDevice = true;
    bump();
  }

  Future<bool> adminCheckPin(String pin) async {
    final s = await Db.i.kv('admin_salt'), h = await Db.i.kv('admin_hash');
    if (s == null || h == null) return false;
    return Sec.eq(Sec.hashSecret(s, pin), h);
  }

  Future<String?> adminAddTeacher(String id, String name, String code) async {
    id = id.trim().toUpperCase();
    name = name.trim();
    if (!RegExp(r'^[A-Z0-9_-]{2,20}$').hasMatch(id) || id == kAdminId) {
      return 'Teacher ID must be 2–20 letters or numbers (no spaces).';
    }
    if (name.isEmpty) return 'Please type the teacher’s name.';
    if (code.length < 4) return 'The access code needs at least 4 characters.';
    final salt = Sec.randomB64(12);
    await Db.i.upsertTeacher(id, name, salt, Sec.hashSecret(salt, code));
    await _rosterChanged();
    return null;
  }

  Future<void> adminRemoveTeacher(String id) async {
    await Db.i.removeTeacher(id);
    for (final pr in peers.values.toList()) {
      if (pr.teacherId == id) _drop(pr.endpointId);
    }
    await _rosterChanged();
  }

  Future<void> _rosterChanged() async {
    rosterVer++;
    await Db.i.setKv('rver', '$rosterVer');
    await reloadRoster();
    for (final pr in peers.values) {
      if (pr.authed) _sendRoster(pr.endpointId);
    }
    bump();
  }

  Future<void> setEnrollment(bool v) async {
    enrollment = v;
    bump();
    if (netId != null) await restart();
  }

  Future<void> setLogo(Uint8List bytes) async {
    await logoFile.writeAsBytes(bytes);
    logoBytes = bytes;
    bump();
  }

  List<Map<String, String>> _rosterPublic() => roster
      .map((e) => {'id': e['id'] as String, 'name': e['name'] as String})
      .toList();

  void _sendRoster(String ep) => _send(ep, {
        't': 'roster',
        'ver': rosterVer,
        'school': school,
        'roster': _rosterPublic(),
      });

  Future<void> _applyRoster(Map<String, dynamic> m) async {
    final ver = m['ver'] as int;
    if (ver <= rosterVer) return;
    await Db.i.applyRoster(m['roster'] as List<dynamic>);
    rosterVer = ver;
    school = (m['school'] as String?) ?? school;
    await Db.i.setKv('rver', '$ver');
    await Db.i.setKv('school', school);
    await reloadRoster();
    for (final pr in peers.values.toList()) {
      if (pr.teacherId.isNotEmpty && !isMember(pr.teacherId)) _drop(pr.endpointId);
    }
    if (myId != null && !isMember(myId!)) {
      removedNotice = 'The school office has removed this Teacher ID from the app.';
      await logout();
      return;
    }
    bump();
  }

  // ======================= Permissions & lifecycle =======================

  Future<bool> ensurePermissions() async {
    await [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();
    final loc = await Permission.locationWhenInUse.status;
    final bt = await Permission.bluetoothConnect.status;
    if (!loc.isGranted && !bt.isGranted) return false;
    try {
      if (!await Permission.locationWhenInUse.serviceStatus.isEnabled) {
        await Nearby().enableLocationServices();
      }
    } catch (_) {}
    return true;
  }

  String _clean(String s) {
    s = s.replaceAll('|', ' ');
    return s.length > 24 ? s.substring(0, 24) : s;
  }

  String get _advName =>
      'SC1|$netId|${_clean(netName)}|${isAdminDevice && enrollment ? 'A' : '-'}';

  Future<void> start() async {
    if (running || _starting || netId == null || key.isEmpty || !visible) return;
    _starting = true;
    error = null;
    bump();
    try {
      if (!await ensurePermissions()) {
        error =
            'School Connect needs Nearby devices / Bluetooth and Location permission. Please allow them in Settings.';
        return;
      }
      await Nearby().startAdvertising(
        _advName,
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: _onInit,
        onConnectionResult: _onResult,
        onDisconnected: _onDisc,
        serviceId: kService,
      );
      await Nearby().startDiscovery(
        _advName,
        Strategy.P2P_CLUSTER,
        onEndpointFound: _onFound,
        onEndpointLost: _onLost,
        serviceId: kService,
      );
      running = true;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 6), (_) => _autoConnect());
    } catch (e) {
      error =
          'Could not start nearby search. Please switch on Bluetooth and Wi-Fi (no internet needed) and Location, then tap Try again.';
      await _stopNearby();
      running = false;
    } finally {
      _starting = false;
      bump();
    }
  }

  Future<void> _stopNearby() async {
    try {
      await Nearby().stopAdvertising();
    } catch (_) {}
    try {
      await Nearby().stopDiscovery();
    } catch (_) {}
    try {
      await Nearby().stopAllEndpoints();
    } catch (_) {}
  }

  Future<void> stop() async {
    _timer?.cancel();
    for (final t in _authTimers.values) {
      t.cancel();
    }
    _authTimers.clear();
    await _stopNearby();
    peers.clear();
    running = false;
    bump();
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  // ======================= Discovery & connections =======================

  bool _parse(Peer pr, String advName) {
    final parts = advName.split('|');
    if (parts.length >= 4 && parts[0] == 'SC1') {
      pr.teacherId = parts[1];
      pr.name = parts[2];
      pr.advAdmin = parts[3] == 'A';
      pr.valid = true;
    } else {
      pr.valid = false;
    }
    return pr.valid;
  }

  void _onFound(String ep, String name, String svc) {
    final pr = peers.putIfAbsent(ep, () => Peer(ep));
    if (!_parse(pr, name)) {
      peers.remove(ep);
      return;
    }
    if (_reg != null) {
      if (pr.advAdmin && pr.state == PeerState.found) {
        regStatus = 'Office phone found. Connecting…';
        _connect(pr);
      }
    } else {
      _autoConnect();
    }
    bump();
  }

  void _onLost(String? ep) {
    if (ep == null) return;
    final pr = peers[ep];
    if (pr != null && !pr.authed) peers.remove(ep);
    bump();
  }

  bool _shouldInitiate(Peer pr) =>
      netId!.compareTo(pr.teacherId) < 0 ||
      DateTime.now().difference(pr.foundAt).inSeconds > 20;

  void _autoConnect() {
    if (_reg != null || netId == null) return;
    final now = DateTime.now();
    for (final pr in peers.values.toList()) {
      if ((pr.state == PeerState.connecting || pr.state == PeerState.verifying) &&
          now.difference(pr.stateAt).inSeconds > 40) {
        pr.state = PeerState.found;
        pr.foundAt = now;
      }
      if (pr.state == PeerState.found &&
          pr.valid &&
          pr.teacherId != netId &&
          isMember(pr.teacherId) &&
          _shouldInitiate(pr)) {
        _connect(pr);
      }
    }
  }

  void _connect(Peer pr) {
    pr.state = PeerState.connecting;
    pr.stateAt = DateTime.now();
    bump();
    Nearby()
        .requestConnection(
      _reg != null ? 'SC1|NEW|New phone|-' : _advName,
      pr.endpointId,
      onConnectionInitiated: _onInit,
      onConnectionResult: _onResult,
      onDisconnected: _onDisc,
    )
        .catchError((_) {
      pr.state = PeerState.found;
      pr.foundAt = DateTime.now();
      bump();
      return false;
    });
  }

  void _onInit(String ep, ConnectionInfo info) {
    final pr = peers.putIfAbsent(ep, () => Peer(ep));
    if (!_parse(pr, info.endpointName)) {
      _drop(ep);
      return;
    }
    pr.state = PeerState.connecting;
    pr.stateAt = DateTime.now();
    Nearby().acceptConnection(
      ep,
      onPayLoadRecieved: _onPayload,
      onPayloadTransferUpdate: _onTransfer,
    );
    _authTimers[ep]?.cancel();
    _authTimers[ep] = Timer(const Duration(seconds: 30), () {
      final q = peers[ep];
      if (q != null && !q.authed && _reg == null) _drop(ep);
    });
    bump();
  }

  void _onResult(String ep, Status s) {
    final pr = peers[ep];
    if (pr == null) return;
    if (s == Status.CONNECTED) {
      pr.state = PeerState.verifying;
      pr.stateAt = DateTime.now();
      if (_reg != null) {
        regStatus = 'Checking your details…';
        _send(ep, {'t': 'reg', 'id': _regId, 'code': _regCode});
      } else if (netId != null) {
        pr.nonce = Sec.randomB64(16);
        _send(ep, {
          't': 'hello',
          'id': netId,
          'name': netName,
          'nonce': pr.nonce,
          'rv': rosterVer,
          'adm': isAdminDevice,
        });
      }
    } else {
      pr.state = PeerState.found;
      pr.foundAt = DateTime.now();
    }
    bump();
  }

  void _onDisc(String ep) {
    _authTimers.remove(ep)?.cancel();
    final pr = peers[ep];
    if (pr != null) {
      if (pr.authed && pr.teacherId.isNotEmpty) {
        Db.i.requeueSending(pr.teacherId);
      }
      pr.state = PeerState.found;
      pr.foundAt = DateTime.now();
      pr.gotHello = false;
      pr.gotProof = false;
      pr.adm = false;
    }
    bump();
  }

  void _drop(String ep) {
    try {
      Nearby().disconnectFromEndpoint(ep);
    } catch (_) {}
    final pr = peers[ep];
    if (pr != null) {
      pr.state = PeerState.found;
      pr.foundAt = DateTime.now();
    }
    bump();
  }

  Future<bool> _send(String ep, Map<String, Object?> m) async {
    try {
      await Nearby()
          .sendBytesPayload(ep, Uint8List.fromList(utf8.encode(jsonEncode(m))));
      return true;
    } catch (_) {
      return false;
    }
  }

  // ======================= Protocol =======================

  void _onPayload(String ep, Payload pl) {
    if (pl.type == PayloadType.BYTES && pl.bytes != null) {
      try {
        final m = jsonDecode(utf8.decode(pl.bytes!)) as Map<String, dynamic>;
        _handle(ep, m);
      } catch (_) {}
    } else if (pl.type == PayloadType.FILE) {
      _filePayloads[pl.id!] = pl;
    }
  }

  Future<void> _handle(String ep, Map<String, dynamic> m) async {
    final pr = peers[ep];
    if (pr == null) return;
    switch (m['t']) {
      case 'reg':
        await _adminReg(ep, pr, m);
        return;
      case 'reg_ok':
        if (_reg != null && !_reg!.isCompleted) {
          await _saveRegistration(m);
          _reg!.complete(null);
        }
        return;
      case 'reg_fail':
        if (_reg != null && !_reg!.isCompleted) {
          _reg!.complete(m['reason'] as String? ?? 'Registration was refused.');
        }
        return;
      case 'hello':
        if (netId == null) return;
        final id = m['id'] as String;
        if (!isMember(id) || id == netId) {
          _drop(ep);
          return;
        }
        pr.teacherId = id;
        pr.name = (m['name'] as String?) ?? pr.name;
        pr.rv = (m['rv'] as int?) ?? 0;
        pr.adm = m['adm'] == true;
        pr.gotHello = true;
        _send(ep, {
          't': 'proof',
          'id': netId,
          'mac': Sec.mac(key, 'proof|${m['nonce']}|$netId'),
        });
        _checkAuth(pr);
        return;
      case 'proof':
        if (netId == null || pr.nonce.isEmpty) return;
        final expected = Sec.mac(key, 'proof|${pr.nonce}|${m['id']}');
        if (!Sec.eq(expected, m['mac'] as String? ?? '') ||
            !isMember(m['id'] as String)) {
          _drop(ep);
          return;
        }
        pr.teacherId = m['id'] as String;
        pr.gotProof = true;
        _checkAuth(pr);
        return;
    }
    // Everything below needs a verified school teacher/office.
    final isLogo = m['t'] == 'file' && m['kind'] == 'logo' && _reg != null;
    if (!pr.authed && !isLogo) return;
    switch (m['t']) {
      case 'roster':
        if (pr.adm) await _applyRoster(m);
        break;
      case 'msg':
        if (m['from'] != pr.teacherId || m['to'] != netId) return;
        final mid = m['mid'] as String;
        if (!await Db.i.hasMsg(mid)) {
          await Db.i.insertMsg(Msg(
              mid: mid,
              peer: pr.teacherId,
              kind: 'text',
              outgoing: false,
              body: m['text'] as String,
              ts: m['ts'] as int,
              status: kSent,
              unread: openChat != pr.teacherId));
        }
        _send(ep, {'t': 'ack', 'mid': mid});
        bump();
        break;
      case 'ack':
        final msg = await Db.i.msg(m['mid'] as String);
        if (msg != null && msg.outgoing && msg.peer == pr.teacherId) {
          await Db.i.setStatus(msg.mid, kDelivered);
          bump();
        }
        break;
      case 'file':
        final pid = m['pid'] as int;
        if (m['kind'] != 'logo' && (m['from'] != pr.teacherId || m['to'] != netId)) {
          return;
        }
        _fileMeta[pid] = m;
        _fileMeta[pid]!['_ep'] = ep;
        if (m['kind'] != 'logo') {
          final mid = m['mid'] as String;
          _inPids[pid] = mid;
          if (!await Db.i.hasMsg(mid)) {
            await Db.i.insertMsg(Msg(
                mid: mid,
                peer: pr.teacherId,
                kind: m['kind'] as String,
                outgoing: false,
                fname: m['fname'] as String,
                size: (m['size'] as int?) ?? 0,
                ts: m['ts'] as int,
                status: kSending,
                unread: openChat != pr.teacherId));
          }
        }
        bump();
        _resolve(pid);
        break;
    }
  }

  void _checkAuth(Peer pr) {
    if (pr.gotHello && pr.gotProof && isMember(pr.teacherId) && !pr.authed) {
      pr.state = PeerState.connected;
      pr.stateAt = DateTime.now();
      _authTimers.remove(pr.endpointId)?.cancel();
      if (isAdminDevice && pr.rv < rosterVer) _sendRoster(pr.endpointId);
      _flush(pr.teacherId);
      bump();
    }
  }

  // ======================= Registration =======================

  Future<void> _adminReg(String ep, Peer pr, Map<String, dynamic> m) async {
    if (!(isAdminDevice && enrollment)) {
      _send(ep, {
        't': 'reg_fail',
        'reason': 'Enrollment is not switched on at the school office phone.'
      });
      return;
    }
    pr.regTries++;
    if (pr.regTries > 3) {
      _drop(ep);
      return;
    }
    final id = (m['id'] as String? ?? '').trim().toUpperCase();
    final code = m['code'] as String? ?? '';
    final t = await Db.i.teacher(id);
    if (t == null ||
        t['verifier'] == null ||
        !Sec.eq(Sec.hashSecret(t['salt'] as String, code), t['verifier'] as String)) {
      await Future.delayed(const Duration(seconds: 2));
      _send(ep, {
        't': 'reg_fail',
        'reason': 'Teacher ID or access code is not correct.'
      });
      return;
    }
    final hasLogo = logoBytes != null && await logoFile.exists();
    await _send(ep, {
      't': 'reg_ok',
      'teacher': {
        'id': id,
        'name': t['name'],
        'salt': t['salt'],
        'verifier': t['verifier']
      },
      'school': school,
      'key': key,
      'ver': rosterVer,
      'roster': _rosterPublic(),
      'logo': hasLogo,
    });
    if (hasLogo) {
      try {
        final pid = await Nearby().sendFilePayload(ep, logoFile.path);
        await _send(ep, {
          't': 'file',
          'kind': 'logo',
          'pid': pid,
          'mid': 'logo',
          'fname': 'logo',
          'size': logoBytes!.length,
          'from': netId,
          'to': '*',
          'ts': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (_) {}
    }
    Timer(const Duration(seconds: 12), () => _drop(ep));
  }

  Future<void> _saveRegistration(Map<String, dynamic> m) async {
    final t = m['teacher'] as Map<String, dynamic>;
    _logoExpected = m['logo'] == true;
    if (_logoExpected) _logoDone = Completer<void>();
    await Db.i.setKv('school', m['school'] as String);
    await Db.i.setKv('key', m['key'] as String);
    await Db.i.setKv('rver', '${m['ver']}');
    await Db.i.upsertTeacher(t['id'] as String, t['name'] as String,
        t['salt'] as String, t['verifier'] as String);
    await Db.i.applyRoster(m['roster'] as List<dynamic>);
    school = m['school'] as String;
    key = m['key'] as String;
    rosterVer = m['ver'] as int;
    await reloadRoster();
    await Db.i.setKv('my_id', t['id'] as String);
    await Db.i.setKv('my_name', t['name'] as String);
    myId = t['id'] as String;
    myName = t['name'] as String;
  }

  /// Returns null on success, or a friendly error message.
  Future<String?> register(String id, String code) async {
    id = id.trim().toUpperCase();
    if (id.isEmpty || code.isEmpty) {
      return 'Please type your Teacher ID and access code.';
    }
    if (_reg != null) return 'Registration is already running.';
    if (!await ensurePermissions()) {
      return 'Please allow Nearby devices / Bluetooth and Location permission, then try again.';
    }
    await stop();
    _regId = id;
    _regCode = code;
    _reg = Completer<String?>();
    regStatus = 'Looking for the school office phone…';
    bump();
    String? result;
    try {
      await Nearby().startDiscovery(
        'SC1|NEW|New phone|-',
        Strategy.P2P_CLUSTER,
        onEndpointFound: _onFound,
        onEndpointLost: _onLost,
        serviceId: kService,
      );
      result = await _reg!.future.timeout(const Duration(seconds: 75),
          onTimeout: () =>
              'The school office phone was not found. Ask the office to switch on “Enrollment”, stay close to that phone and try again.');
      if (result == null && _logoExpected && _logoDone != null) {
        await _logoDone!.future
            .timeout(const Duration(seconds: 10), onTimeout: () {});
      }
    } catch (_) {
      result =
          'Could not search for the office phone. Please switch on Bluetooth, Wi-Fi and Location.';
    }
    _reg = null;
    _regId = null;
    _regCode = null;
    _logoExpected = false;
    _logoDone = null;
    regStatus = '';
    await _stopNearby();
    peers.clear();
    bump();
    if (result == null) start();
    return result;
  }

  // ======================= Sending =======================

  String? _endpointFor(String teacherId) {
    for (final pr in peers.values.toList().reversed) {
      if (pr.authed && pr.teacherId == teacherId) return pr.endpointId;
    }
    return null;
  }

  PeerState? stateOf(String teacherId) {
    PeerState? best;
    for (final pr in peers.values) {
      if (pr.teacherId != teacherId) continue;
      if (best == null || pr.state.index > best.index) best = pr.state;
    }
    return best;
  }

  bool isOnline(String teacherId) => _endpointFor(teacherId) != null;
  int get connectedCount => peers.values.where((e) => e.authed).length;

  Future<void> sendText(String peerId, String text) async {
    final m = Msg(
        mid: Sec.uid(),
        peer: peerId,
        kind: 'text',
        outgoing: true,
        body: text,
        ts: DateTime.now().millisecondsSinceEpoch,
        status: kQueued);
    await Db.i.insertMsg(m);
    bump();
    await _deliver(m);
  }

  Future<void> sendFile(String peerId, File src, String kind, String fname) async {
    final mid = Sec.uid();
    final safe = fname.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    final dest = p.join(mediaDir.path, '${mid}_$safe');
    await src.copy(dest);
    final m = Msg(
        mid: mid,
        peer: peerId,
        kind: kind,
        outgoing: true,
        fname: fname,
        path: dest,
        size: await File(dest).length(),
        ts: DateTime.now().millisecondsSinceEpoch,
        status: kQueued);
    await Db.i.insertMsg(m);
    bump();
    await _deliver(m);
  }

  Future<void> retry(Msg m) async {
    await Db.i.setStatus(m.mid, kQueued);
    m.status = kQueued;
    bump();
    await _deliver(m);
  }

  Future<void> _flush(String teacherId) async {
    for (final m in await Db.i.outbox(teacherId)) {
      await _deliver(m);
    }
  }

  Future<void> _deliver(Msg m) async {
    final ep = _endpointFor(m.peer);
    if (ep == null) return; // stays queued; sent automatically when in range
    if (m.kind == 'text') {
      final ok = await _send(ep, {
        't': 'msg',
        'mid': m.mid,
        'from': netId,
        'to': m.peer,
        'text': m.body,
        'ts': m.ts
      });
      await Db.i.setStatus(m.mid, ok ? kSent : kFailed);
      bump();
      return;
    }
    if (m.path == null || !await File(m.path!).exists()) {
      await Db.i.setStatus(m.mid, kFailed);
      bump();
      return;
    }
    await Db.i.setStatus(m.mid, kSending);
    progress[m.mid] = 0;
    bump();
    try {
      final pid = await Nearby().sendFilePayload(ep, m.path!);
      _outPids[pid] = m.mid;
      await _send(ep, {
        't': 'file',
        'mid': m.mid,
        'from': netId,
        'to': m.peer,
        'kind': m.kind,
        'fname': m.fname,
        'size': m.size,
        'ts': m.ts,
        'pid': pid,
      });
      _resolve(pid);
    } catch (_) {
      await Db.i.setStatus(m.mid, kFailed);
      progress.remove(m.mid);
      bump();
    }
  }

  // ======================= File transfer =======================

  void _onTransfer(String ep, PayloadTransferUpdate u) {
    _xfer[u.id] = u.status;
    final mid = _outPids[u.id] ?? _inPids[u.id];
    if (mid != null && u.totalBytes > 0) {
      progress[mid] = u.bytesTransferred / u.totalBytes;
    }
    bump();
    _resolve(u.id);
  }

  Future<void> _resolve(int pid) async {
    final st = _xfer[pid];
    if (st == null ||
        st == PayloadStatus.IN_PROGRESS ||
        st == PayloadStatus.NONE) {
      return;
    }
    final ok = st == PayloadStatus.SUCCESS;
    if (_outPids.containsKey(pid)) {
      final mid = _outPids.remove(pid)!;
      await Db.i.setStatus(mid, ok ? kSent : kFailed);
      progress.remove(mid);
      _xfer.remove(pid);
      bump();
      return;
    }
    final meta = _fileMeta[pid];
    if (meta == null) return; // wait for the description message
    if (!ok) {
      final mid = _inPids.remove(pid);
      if (mid != null) {
        await Db.i.setStatus(mid, kFailed);
        progress.remove(mid);
      }
      _fileMeta.remove(pid);
      _filePayloads.remove(pid);
      _xfer.remove(pid);
      bump();
      return;
    }
    final pl = _filePayloads[pid];
    if (pl == null) return;
    _fileMeta.remove(pid);
    _filePayloads.remove(pid);
    _xfer.remove(pid);
    final isLogo = meta['kind'] == 'logo';
    final mid = meta['mid'] as String;
    final fname = (meta['fname'] as String).replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    final dest = isLogo
        ? logoFile.path
        : p.join(mediaDir.path, '${mid}_$fname');
    var saved = false;
    try {
      if (await File(dest).exists()) await File(dest).delete();
      final uri = pl.uri;
      if (uri != null && uri.isNotEmpty) {
        saved = await Nearby().copyFileAndDeleteOriginal(uri, dest);
      } else if (pl.filePath != null) {
        await File(pl.filePath!).copy(dest);
        await File(pl.filePath!).delete();
        saved = true;
      }
    } catch (_) {
      saved = false;
    }
    if (isLogo) {
      if (saved) {
        logoBytes = await File(dest).readAsBytes();
      }
      _logoDone?.complete();
      bump();
      return;
    }
    _inPids.remove(pid);
    progress.remove(mid);
    if (saved) {
      await Db.i.setFileDone(mid, dest, await File(dest).length());
      final ep = meta['_ep'] as String?;
      if (ep != null) _send(ep, {'t': 'ack', 'mid': mid});
    } else {
      await Db.i.setStatus(mid, kFailed);
    }
    bump();
  }
}

import 'package:flutter/material.dart';
import '../db.dart';
import '../mesh.dart';
import '../models.dart';
import '../util.dart';
import 'chat.dart';
import 'settings.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeState();
}

class _HomeState extends State<HomeScreen> {
  List<Map<String, Object?>> convs = [];
  String q = '';
  bool searching = false;

  @override
  void initState() {
    super.initState();
    Mesh.i.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Mesh.i.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    var c = await Db.i.conversations();
    if (q.isNotEmpty) {
      final hits = await Db.i.searchPeers(q);
      final ql = q.toLowerCase();
      c = c.where((e) {
        final peer = e['peer'] as String;
        return Mesh.i.nameOf(peer).toLowerCase().contains(ql) ||
            peer.toLowerCase().contains(ql) ||
            hits.contains(peer);
      }).toList();
    }
    if (mounted) setState(() => convs = c);
  }

  String _preview(Map<String, Object?> e) {
    switch (e['kind']) {
      case 'image':
        return '📷 Photo';
      case 'pdf':
        return '📄 ${e['fname'] ?? 'PDF document'}';
      default:
        return (e['body'] as String?) ?? '';
    }
  }

  void _open(String peer) => Navigator.push(
          context, MaterialPageRoute(builder: (_) => ChatScreen(peerId: peer)))
      .then((_) => _load());

  Widget _banner() {
    final m = Mesh.i;
    if (m.error != null) {
      return Container(
        color: Colors.orange.shade100,
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Icon(Icons.warning_amber, color: Colors.deepOrange),
          const SizedBox(width: 10),
          Expanded(child: Text(m.error!, style: const TextStyle(fontSize: 15))),
          TextButton(onPressed: m.restart, child: const Text('Try again')),
        ]),
      );
    }
    final n = m.connectedCount;
    return Container(
      color: n > 0 ? const Color(0xFFE8F5E9) : Colors.grey.shade200,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        statusDot(n > 0 ? kAccent : Colors.grey),
        const SizedBox(width: 10),
        Expanded(
            child: Text(
                !m.visible
                    ? 'Nearby search is switched off (Settings)'
                    : n > 0
                        ? 'Connected to $n nearby ${n == 1 ? 'teacher' : 'teachers'}'
                        : 'Searching for teachers nearby…',
                style: const TextStyle(fontSize: 16))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          titleSpacing: 8,
          title: searching
              ? TextField(
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  cursorColor: Colors.white,
                  decoration: const InputDecoration(
                      hintText: 'Search teachers or messages',
                      hintStyle: TextStyle(color: Colors.white70),
                      border: InputBorder.none),
                  onChanged: (v) {
                    q = v.trim();
                    _load();
                  })
              : Row(children: [
                  const SchoolLogo(size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(Mesh.i.school.isEmpty ? 'School Connect' : Mesh.i.school,
                          overflow: TextOverflow.ellipsis)),
                ]),
          actions: [
            IconButton(
                icon: Icon(searching ? Icons.close : Icons.search),
                onPressed: () => setState(() {
                      searching = !searching;
                      q = '';
                      _load();
                    })),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'nearby') {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const NearbyScreen()));
                } else if (v == 'profile') {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ChatProfileRoute.me()));
                } else {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'nearby', child: Text('Nearby teachers')),
                PopupMenuItem(value: 'profile', child: Text('My profile')),
                PopupMenuItem(value: 'settings', child: Text('Settings')),
              ],
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NearbyScreen())).then((_) => _load()),
          child: const Icon(Icons.chat),
        ),
        body: ListenableBuilder(
          listenable: Mesh.i,
          builder: (_, __) => Column(children: [
            _banner(),
            Expanded(
              child: convs.isEmpty
                  ? Center(
                      child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                              q.isNotEmpty
                                  ? 'No conversations found.'
                                  : 'No chats yet.\nTap the green button to choose a teacher.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 18, color: Colors.black54))))
                  : ListView.separated(
                      itemCount: convs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                      itemBuilder: (_, i) {
                        final e = convs[i];
                        final peer = e['peer'] as String;
                        final name = Mesh.i.nameOf(peer);
                        final unread = (e['unread'] as int?) ?? 0;
                        final out = e['outgoing'] == 1;
                        return ListTile(
                          minVerticalPadding: 12,
                          leading: Stack(children: [
                            Avatar(name),
                            if (Mesh.i.isOnline(peer))
                              Positioned(right: 0, bottom: 0, child: statusDot(kAccent)),
                          ]),
                          title: Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          subtitle: Row(children: [
                            if (out)
                              Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(
                                      e['status'] == kDelivered
                                          ? Icons.done_all
                                          : e['status'] == kFailed
                                              ? Icons.error_outline
                                              : e['status'] == kQueued
                                                  ? Icons.access_time
                                                  : Icons.done,
                                      size: 16,
                                      color: e['status'] == kFailed ? Colors.red : Colors.grey)),
                            Expanded(child: Text(_preview(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16))),
                          ]),
                          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(fmtTime(e['ts'] as int),
                                style: TextStyle(fontSize: 13, color: unread > 0 ? kGreen2 : Colors.grey)),
                            if (unread > 0)
                              Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(12)),
                                  child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
                          ]),
                          onTap: () => _open(peer),
                        );
                      },
                    ),
            ),
          ]),
        ),
      );
}

// ---------------------------------------------------------------- Nearby
class NearbyScreen extends StatelessWidget {
  const NearbyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Nearby teachers'), actions: [
          IconButton(
              tooltip: 'Search again',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                Mesh.i.restart();
                snack(context, 'Searching again…');
              }),
        ]),
        body: ListenableBuilder(
          listenable: Mesh.i,
          builder: (_, __) {
            final m = Mesh.i;
            final rows = <Map<String, Object?>>[
              ...m.roster.where((r) => r['id'] != m.myId),
              if (m.myId != null && m.stateOf(kAdminId) != null)
                {'id': kAdminId, 'name': 'School Office'},
            ];
            rows.sort((a, b) {
              final sa = m.stateOf(a['id'] as String)?.index ?? -1;
              final sb = m.stateOf(b['id'] as String)?.index ?? -1;
              return sb.compareTo(sa);
            });
            return Column(children: [
              Container(
                width: double.infinity,
                color: const Color(0xFFE8F5E9),
                padding: const EdgeInsets.all(14),
                child: Text(
                    m.error ??
                        'Teachers connect automatically when phones are close (about 30–100 metres). Keep Bluetooth, Wi-Fi and Location switched on. No internet needed.',
                    style: const TextStyle(fontSize: 15)),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(child: Text('No teachers registered yet.', style: TextStyle(fontSize: 18)))
                    : ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                        itemBuilder: (_, i) {
                          final id = rows[i]['id'] as String;
                          final name = rows[i]['name'] as String;
                          final st = m.stateOf(id);
                          final online = m.isOnline(id);
                          final label = online
                              ? 'Connected'
                              : st == PeerState.verifying
                                  ? 'Verifying…'
                                  : st == PeerState.connecting
                                      ? 'Connecting…'
                                      : st == PeerState.found
                                          ? 'Nearby – connecting soon'
                                          : 'Not nearby';
                          return ListTile(
                            minVerticalPadding: 12,
                            leading: Avatar(name),
                            title: Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                            subtitle: Row(children: [
                              statusDot(online ? kAccent : st != null ? Colors.orange : Colors.grey),
                              const SizedBox(width: 8),
                              Text('$label  •  ID $id', style: const TextStyle(fontSize: 15)),
                            ]),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peerId: id))),
                          );
                        }),
              ),
            ]);
          },
        ),
      );
}

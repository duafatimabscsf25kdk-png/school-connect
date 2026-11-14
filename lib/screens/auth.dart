import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../db.dart';
import '../mesh.dart';
import '../security.dart';
import '../util.dart';

// ---------------------------------------------------------------- Welcome
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeState();
}

class _WelcomeState extends State<WelcomeScreen> {
  final _id = TextEditingController(), _code = TextEditingController();
  String? _err;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _err = Mesh.i.removedNotice;
    Mesh.i.removedNotice = null;
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    final e = await Mesh.i.login(_id.text, _code.text);
    if (mounted) setState(() {
      _busy = false;
      _err = e;
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = Mesh.i;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(children: [
                Container(
                    decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle),
                    padding: const EdgeInsets.all(6),
                    child: SchoolLogo(size: 96)),
                const SizedBox(height: 16),
                Text(m.school.isEmpty ? 'School Connect' : m.school,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: kGreen)),
                const Text('Offline Teacher Messenger', style: TextStyle(fontSize: 17, color: Colors.black54)),
                const SizedBox(height: 28),
                TextField(
                    controller: _id,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(fontSize: 20),
                    decoration: const InputDecoration(labelText: 'Teacher ID', prefixIcon: Icon(Icons.badge))),
                const SizedBox(height: 14),
                TextField(
                    controller: _code,
                    obscureText: true,
                    style: const TextStyle(fontSize: 20),
                    decoration: const InputDecoration(labelText: 'Access code', prefixIcon: Icon(Icons.lock))),
                if (_err != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_err!, style: const TextStyle(color: Colors.red, fontSize: 16))),
                const SizedBox(height: 20),
                bigButton(_busy ? 'Please wait…' : 'Log in', _busy ? null : _login, icon: Icons.login),
                const SizedBox(height: 12),
                bigButton('Register this phone (first time)',
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                    icon: Icons.phone_android, outlined: true),
                const SizedBox(height: 8),
                TextButton(
                    onPressed: () => openAdmin(context),
                    child: const Text('School administrator', style: TextStyle(fontSize: 16))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Register
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterState();
}

class _RegisterState extends State<RegisterScreen> {
  final _id = TextEditingController(), _code = TextEditingController();
  String? _err;
  bool _busy = false;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    final e = await Mesh.i.register(_id.text, _code.text);
    if (!mounted) return;
    if (e == null) {
      Navigator.popUntil(context, (r) => r.isFirst);
    } else {
      setState(() {
        _busy = false;
        _err = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Register this phone')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Card(
              color: const Color(0xFFE8F5E9),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                    '1. Ask the school office to open the Administrator panel and switch on “Enrollment”.\n'
                    '2. Stand close to the office phone.\n'
                    '3. Type your Teacher ID and access code (given by the office) and tap Register.\n\n'
                    'No internet is needed. You only do this once.',
                    style: TextStyle(fontSize: 17, height: 1.4)),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
                controller: _id,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontSize: 20),
                decoration: const InputDecoration(labelText: 'Teacher ID', prefixIcon: Icon(Icons.badge))),
            const SizedBox(height: 14),
            TextField(
                controller: _code,
                obscureText: true,
                style: const TextStyle(fontSize: 20),
                decoration: const InputDecoration(labelText: 'Access code', prefixIcon: Icon(Icons.lock))),
            const SizedBox(height: 20),
            ListenableBuilder(
                listenable: Mesh.i,
                builder: (_, __) => _busy
                    ? Row(children: [
                        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(Mesh.i.regStatus, style: const TextStyle(fontSize: 17))),
                      ])
                    : const SizedBox.shrink()),
            if (_err != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_err!, style: const TextStyle(color: Colors.red, fontSize: 16))),
            const SizedBox(height: 20),
            bigButton('Register', _busy ? null : _go, icon: Icons.how_to_reg),
          ]),
        ),
      );
}

// ---------------------------------------------------------------- Admin gate
Future<void> openAdmin(BuildContext context) async {
  final m = Mesh.i;
  if (!m.isAdminDevice) {
    if (m.school.isNotEmpty) {
      snack(context,
          'This phone is a teacher phone. The administrator panel can only be created on the school office phone.');
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSetupScreen()));
    return;
  }
  final pin = await askText(context, 'Administrator PIN', 'PIN', obscure: true, type: TextInputType.number);
  if (pin == null || !context.mounted) return;
  if (!await m.adminCheckPin(pin)) {
    if (context.mounted) snack(context, 'Wrong PIN.');
    return;
  }
  if (context.mounted) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanel()));
  }
}

class AdminSetupScreen extends StatefulWidget {
  const AdminSetupScreen({super.key});
  @override
  State<AdminSetupScreen> createState() => _AdminSetupState();
}

class _AdminSetupState extends State<AdminSetupScreen> {
  final _name = TextEditingController(), _pin = TextEditingController(), _pin2 = TextEditingController();
  String? _err;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return setState(() => _err = 'Please type the school name.');
    if (_pin.text.length < 4) return setState(() => _err = 'The PIN needs at least 4 digits.');
    if (_pin.text != _pin2.text) return setState(() => _err = 'The two PINs are different.');
    await Mesh.i.adminSetup(_name.text, _pin.text);
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminPanel()));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Set up school office phone')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const Text(
                'Do this ONLY on the one phone that the school office will use to add and remove teachers.',
                style: TextStyle(fontSize: 17)),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'School name')),
            const SizedBox(height: 14),
            TextField(
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Administrator PIN (4+ digits)')),
            const SizedBox(height: 14),
            TextField(
                controller: _pin2,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Repeat PIN')),
            if (_err != null)
              Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: Colors.red, fontSize: 16))),
            const SizedBox(height: 20),
            bigButton('Create administrator panel', _save, icon: Icons.admin_panel_settings),
          ]),
        ),
      );
}

// ---------------------------------------------------------------- Admin panel
class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});
  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  List<Map<String, Object?>> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (!Mesh.i.loggedIn && !Mesh.i.enrollment) Mesh.i.stop();
    super.dispose();
  }

  Future<void> _load() async {
    final l = await Db.i.roster();
    if (mounted) setState(() => _list = l);
  }

  Future<void> _add() async {
    final id = TextEditingController(), name = TextEditingController();
    final code = TextEditingController(text: Sec.randomDigits(6));
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Add / update teacher'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: id, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Teacher ID (e.g. T101)')),
              const SizedBox(height: 10),
              TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Teacher name')),
              const SizedBox(height: 10),
              TextField(controller: code, decoration: const InputDecoration(labelText: 'Access code')),
              if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: Colors.red))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
                onPressed: () async {
                  final e = await Mesh.i.adminAddTeacher(id.text, name.text, code.text.trim());
                  if (e == null) {
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } else {
                    setD(() => err = e);
                  }
                },
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      await _load();
      if (!mounted) return;
      await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
                title: const Text('Give this to the teacher'),
                content: Text(
                    'Teacher ID: ${id.text.trim().toUpperCase()}\nAccess code: ${code.text.trim()}\n\nThe code cannot be shown again.',
                    style: const TextStyle(fontSize: 18, height: 1.5)),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
              ));
    }
  }

  Future<void> _logo() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 256, maxHeight: 256, imageQuality: 85);
    if (x == null) return;
    await Mesh.i.setLogo(await x.readAsBytes());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('School administrator')),
        floatingActionButton:
            FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.person_add), label: const Text('Add teacher')),
        body: ListenableBuilder(
          listenable: Mesh.i,
          builder: (_, __) => ListView(padding: const EdgeInsets.only(bottom: 90), children: [
            ListTile(
              leading: const SchoolLogo(size: 48),
              title: Text(Mesh.i.school, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Tap to change school logo'),
              onTap: _logo,
            ),
            SwitchListTile(
              title: const Text('Enrollment', style: TextStyle(fontSize: 18)),
              subtitle: const Text('Switch ON so teachers can register their phones near this phone. Switch OFF afterwards.'),
              value: Mesh.i.enrollment,
              onChanged: (v) async {
                await Mesh.i.setEnrollment(v);
                if (Mesh.i.error != null && mounted) snack(context, Mesh.i.error!);
              },
            ),
            if (Mesh.i.enrollment)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                      'Enrollment is ON. Phones connected now: ${Mesh.i.connectedCount}. Searching: ${Mesh.i.running ? 'yes' : 'no'}',
                      style: const TextStyle(color: kGreen))),
            const Divider(),
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Registered teachers (${_list.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
            if (_list.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('No teachers yet. Tap “Add teacher”.', style: TextStyle(fontSize: 16))),
            for (final t in _list)
              ListTile(
                leading: Avatar(t['name'] as String),
                title: Text(t['name'] as String),
                subtitle: Text('ID: ${t['id']}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    if (await confirm(context, 'Remove teacher?', '${t['name']} will lose access when their phone next meets another teacher’s phone or the office phone.')) {
                      await Mesh.i.adminRemoveTeacher(t['id'] as String);
                      _load();
                    }
                  },
                ),
              ),
          ]),
        ),
      );
}

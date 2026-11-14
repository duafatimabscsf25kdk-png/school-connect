import 'package:flutter/material.dart';
import '../db.dart';
import '../mesh.dart';
import '../util.dart';
import 'auth.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListenableBuilder(
          listenable: Mesh.i,
          builder: (_, __) {
            final m = Mesh.i;
            return ListView(children: [
              SwitchListTile(
                secondary: const Icon(Icons.text_fields, color: kGreen2),
                title: const Text('Large text', style: TextStyle(fontSize: 18)),
                value: m.largeText,
                onChanged: m.setLarge,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.bluetooth_searching, color: kGreen2),
                title: const Text('Find & connect to nearby teachers', style: TextStyle(fontSize: 18)),
                subtitle: const Text('Keep this ON to send and receive messages.'),
                value: m.visible,
                onChanged: m.setVisible,
              ),
              ListTile(
                leading: const Icon(Icons.refresh, color: kGreen2),
                title: const Text('Search again for teachers', style: TextStyle(fontSize: 18)),
                onTap: () {
                  m.restart();
                  snack(context, 'Searching again…');
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder, color: kGreen2),
                title: const Text('Received files', style: TextStyle(fontSize: 18)),
                subtitle: Text('Saved automatically inside the app:\n${m.mediaDir.path}'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep, color: Colors.red),
                title: const Text('Delete all chats on this phone', style: TextStyle(fontSize: 18)),
                onTap: () async {
                  if (await confirm(context, 'Delete all chats?', 'Every message on this phone will be deleted.')) {
                    await Db.i.clearAll();
                    m.bump();
                    if (context.mounted) snack(context, 'All chats deleted.');
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings, color: kGreen2),
                title: const Text('School administrator', style: TextStyle(fontSize: 18)),
                onTap: () => openAdmin(context),
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: kGreen2),
                title: const Text('Log out', style: TextStyle(fontSize: 18)),
                onTap: () async {
                  if (await confirm(context, 'Log out?', 'Your chats stay on this phone.')) {
                    if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
                    await m.logout();
                  }
                },
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'School Connect works without internet using Bluetooth and Wi-Fi through Google Nearby Connections. '
                    'Keep the app open while you expect messages. Messages for teachers who are not nearby are sent automatically when you meet.',
                    style: TextStyle(fontSize: 15, color: Colors.black54)),
              ),
            ]);
          },
        ),
      );
}

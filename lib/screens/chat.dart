import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import '../db.dart';
import '../mesh.dart';
import '../models.dart';
import '../util.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.peerId});
  final String peerId;
  @override
  State<ChatScreen> createState() => _ChatState();
}

class _ChatState extends State<ChatScreen> {
  final _c = TextEditingController();
  List<Msg> msgs = [];

  @override
  void initState() {
    super.initState();
    Mesh.i.openChat = widget.peerId;
    Mesh.i.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Mesh.i.openChat = null;
    Mesh.i.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final l = await Db.i.messages(widget.peerId);
    await Db.i.markRead(widget.peerId);
    if (mounted) setState(() => msgs = l);
  }

  Future<void> _sendText() async {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    _c.clear();
    await Mesh.i.sendText(widget.peerId, t);
  }

  Future<void> _pickImage(ImageSource s) async {
    final x = await ImagePicker().pickImage(source: s, maxWidth: 1600, imageQuality: 85);
    if (x == null) return;
    final ext = p.extension(x.path).toLowerCase();
    if (!['.jpg', '.jpeg', '.png'].contains(ext)) {
      if (mounted) snack(context, 'Only JPG, JPEG and PNG photos can be sent.');
      return;
    }
    await Mesh.i.sendFile(widget.peerId, File(x.path), 'image', p.basename(x.path));
  }

  Future<void> _pickPdf() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final f = r?.files.single;
    if (f == null || f.path == null) return;
    if (f.size > 50 * 1024 * 1024) {
      if (mounted) snack(context, 'This PDF is bigger than 50 MB. Please choose a smaller file.');
      return;
    }
    await Mesh.i.sendFile(widget.peerId, File(f.path!), 'pdf', f.name);
  }

  void _attach() => showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                leading: const Icon(Icons.photo, color: kGreen2, size: 32),
                title: const Text('Photo from gallery', style: TextStyle(fontSize: 18)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                }),
            ListTile(
                leading: const Icon(Icons.camera_alt, color: kGreen2, size: 32),
                title: const Text('Take a photo', style: TextStyle(fontSize: 18)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                }),
            ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 32),
                title: const Text('PDF document', style: TextStyle(fontSize: 18)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPdf();
                }),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final name = Mesh.i.nameOf(widget.peerId);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(peerId: widget.peerId))),
          child: ListenableBuilder(
            listenable: Mesh.i,
            builder: (_, __) => Row(children: [
              Avatar(name, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, overflow: TextOverflow.ellipsis),
                Text(Mesh.i.isOnline(widget.peerId) ? 'connected' : 'not nearby – messages wait and send automatically',
                    style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.normal)),
              ])),
            ]),
          ),
        ),
      ),
      body: Container(
        color: kChatBg,
        child: Column(children: [
          Expanded(
            child: msgs.isEmpty
                ? const Center(child: Text('Say hello 👋', style: TextStyle(fontSize: 18, color: Colors.black54)))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) => _Bubble(msgs[msgs.length - 1 - i]),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
                    child: Row(children: [
                      IconButton(icon: const Icon(Icons.attach_file, color: Colors.grey, size: 28), onPressed: _attach),
                      Expanded(
                          child: TextField(
                        controller: _c,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(fontSize: 18),
                        decoration: const InputDecoration(hintText: 'Type a message', border: InputBorder.none),
                      )),
                    ]),
                  ),
                ),
                const SizedBox(width: 6),
                CircleAvatar(
                    radius: 26,
                    backgroundColor: kGreen2,
                    child: IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: _sendText)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.m);
  final Msg m;

  Widget _tick() {
    if (!m.outgoing) return const SizedBox.shrink();
    switch (m.status) {
      case kQueued:
        return const Icon(Icons.access_time, size: 15, color: Colors.grey);
      case kSending:
        return const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2));
      case kSent:
        return const Icon(Icons.done, size: 16, color: Colors.grey);
      case kDelivered:
        return const Icon(Icons.done_all, size: 16, color: kGreen2);
      default:
        return const Icon(Icons.error, size: 16, color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mesh = Mesh.i;
    final failed = m.status == kFailed;
    Widget content;
    if (m.kind == 'text') {
      content = Text(m.body ?? '', style: const TextStyle(fontSize: 18));
    } else {
      final busy = m.status == kSending;
      final prog = mesh.progress[m.mid];
      final ready = fileExists(m.path);
      Widget top;
      if (m.kind == 'image' && ready) {
        top = GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _Viewer(m.path!))),
          child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(m.path!), width: 220, cacheWidth: 600, fit: BoxFit.cover)),
        );
      } else {
        top = InkWell(
          onTap: ready && m.kind == 'pdf' ? () => OpenFilex.open(m.path!) : null,
          child: Container(
            width: 230,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(m.kind == 'pdf' ? Icons.picture_as_pdf : Icons.image, color: m.kind == 'pdf' ? Colors.red : kGreen2, size: 36),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.fname ?? 'file', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
                Text(m.kind == 'pdf' ? 'PDF • ${fmtSize(m.size)}${ready ? ' • tap to open' : ''}' : fmtSize(m.size),
                    style: const TextStyle(fontSize: 13, color: Colors.black54)),
              ])),
            ]),
          ),
        );
      }
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        top,
        if (busy)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                  width: 220,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    LinearProgressIndicator(value: prog, color: kGreen2),
                    Text(prog == null ? 'Starting…' : '${(prog * 100).round()}%  ${m.outgoing ? 'sending' : 'receiving'}',
                        style: const TextStyle(fontSize: 12)),
                  ]))),
      ]);
    }
    return Align(
      alignment: m.outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: failed && m.outgoing ? () => mesh.retry(m) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          decoration: BoxDecoration(
              color: m.outgoing ? kBubbleOut : Colors.white,
              borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(m.outgoing ? 14 : 2),
                  bottomRight: Radius.circular(m.outgoing ? 2 : 14))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Align(alignment: Alignment.centerLeft, child: content),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (failed) Text(m.outgoing ? 'Failed – tap to retry  ' : 'Failed  ', style: const TextStyle(fontSize: 12, color: Colors.red)),
              Text(fmtClock(m.ts), style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(width: 4),
              _tick(),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Viewer extends StatelessWidget {
  const _Viewer(this.path);
  final String path;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: Center(child: InteractiveViewer(child: Image.file(File(path)))),
      );
}

// ---------------------------------------------------------------- Profile
class ChatProfileRoute {
  static Widget me() => ProfileScreen(peerId: Mesh.i.myId!);
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.peerId});
  final String peerId;

  @override
  Widget build(BuildContext context) {
    final m = Mesh.i;
    final isMe = peerId == m.myId;
    final name = isMe ? (m.myName ?? peerId) : m.nameOf(peerId);
    return Scaffold(
      appBar: AppBar(title: Text(isMe ? 'My profile' : 'Teacher profile')),
      body: ListenableBuilder(
        listenable: m,
        builder: (_, __) => ListView(padding: const EdgeInsets.all(20), children: [
          Center(child: Avatar(name, radius: 56)),
          const SizedBox(height: 14),
          Center(child: Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
          const SizedBox(height: 20),
          ListTile(leading: const Icon(Icons.badge, color: kGreen2), title: const Text('Teacher ID'), subtitle: Text(peerId, style: const TextStyle(fontSize: 18))),
          ListTile(leading: const Icon(Icons.school, color: kGreen2), title: const Text('School'), subtitle: Text(m.school, style: const TextStyle(fontSize: 18))),
          if (!isMe)
            ListTile(
                leading: statusDot(m.isOnline(peerId) ? kAccent : Colors.grey),
                title: const Text('Connection'),
                subtitle: Text(m.isOnline(peerId) ? 'Connected – nearby' : 'Not nearby right now', style: const TextStyle(fontSize: 18))),
          const SizedBox(height: 16),
          if (!isMe) ...[
            bigButton('Delete this chat', () async {
              if (await confirm(context, 'Delete chat?', 'All messages with $name will be deleted from this phone.')) {
                await Db.i.clearChat(peerId);
                m.bump();
                if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
              }
            }, icon: Icons.delete, outlined: true),
          ] else
            bigButton('Log out', () async {
              if (await confirm(context, 'Log out?', 'Your chats stay on this phone. You can log in again with your access code.')) {
                if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
                await m.logout();
              }
            }, icon: Icons.logout, outlined: true),
        ]),
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'mesh.dart';

const kGreen = Color(0xFF075E54);
const kGreen2 = Color(0xFF128C7E);
const kAccent = Color(0xFF25D366);
const kBubbleOut = Color(0xFFDCF8C6);
const kChatBg = Color(0xFFECE5DD);

String two(int n) => n.toString().padLeft(2, '0');

String fmtTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final n = DateTime.now();
  bool same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  if (same(d, n)) return '${two(d.hour)}:${two(d.minute)}';
  if (same(d, n.subtract(const Duration(days: 1)))) return 'Yesterday';
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

String fmtClock(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${two(d.hour)}:${two(d.minute)}';
}

String fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

void snack(BuildContext c, String s) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(s, style: const TextStyle(fontSize: 16))));
}

Future<String?> askText(BuildContext c, String title, String label,
    {bool obscure = false, TextInputType? type}) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
          controller: ctl,
          obscureText: obscure,
          autofocus: true,
          keyboardType: type,
          decoration: InputDecoration(labelText: label)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('OK')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext c, String title, String msg) async =>
    (await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    )) ==
    true;

class SchoolLogo extends StatelessWidget {
  const SchoolLogo({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) {
    final b = Mesh.i.logoBytes;
    if (b != null) {
      return ClipOval(child: Image.memory(b, width: size, height: size, fit: BoxFit.cover));
    }
    return CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.white,
        child: Icon(Icons.school, color: kGreen, size: size * 0.6));
  }
}

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.radius = 24});
  final String name;
  final double radius;
  @override
  Widget build(BuildContext context) => CircleAvatar(
      radius: radius,
      backgroundColor: kGreen2,
      child: Text(name.isEmpty ? '?' : name.trim()[0].toUpperCase(),
          style: TextStyle(color: Colors.white, fontSize: radius * 0.9, fontWeight: FontWeight.w600)));
}

Widget bigButton(String text, VoidCallback? onTap,
        {IconData? icon, bool outlined = false}) =>
    SizedBox(
      width: double.infinity,
      height: 56,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon ?? Icons.arrow_forward),
              label: Text(text, style: const TextStyle(fontSize: 18)),
              style: OutlinedButton.styleFrom(foregroundColor: kGreen, side: const BorderSide(color: kGreen, width: 1.5)))
          : ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icon ?? Icons.arrow_forward),
              label: Text(text, style: const TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(backgroundColor: kGreen2, foregroundColor: Colors.white)),
    );

Widget statusDot(Color c) => Container(
    width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

bool fileExists(String? p) => p != null && File(p).existsSync();

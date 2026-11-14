import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class Sec {
  static final Random _r = Random.secure();

  static String randomB64(int n) =>
      base64Encode(List<int>.generate(n, (_) => _r.nextInt(256)));

  static String randomDigits(int n) =>
      List.generate(n, (_) => _r.nextInt(10)).join();

  /// Salted, iterated SHA-256 of an access code / PIN.
  static String hashSecret(String salt, String secret) {
    var h = utf8.encode('$salt|$secret');
    for (var i = 0; i < 5000; i++) {
      h = sha256.convert(h).bytes;
    }
    return base64Encode(h);
  }

  static String mac(String keyB64, String data) =>
      Hmac(sha256, base64Decode(keyB64)).convert(utf8.encode(data)).toString();

  static bool eq(String a, String b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return d == 0;
  }

  static String uid() =>
      '${DateTime.now().microsecondsSinceEpoch}${randomB64(6).replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}';
}

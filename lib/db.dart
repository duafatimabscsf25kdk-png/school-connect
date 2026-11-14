import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'models.dart';

class Db {
  Db._();
  static final Db i = Db._();
  late Database d;

  Future<void> init() async {
    d = await openDatabase(
      p.join(await getDatabasesPath(), 'school_connect.db'),
      version: 1,
      onCreate: (db, v) async {
        await db.execute('CREATE TABLE kv(k TEXT PRIMARY KEY, v TEXT)');
        await db.execute(
            'CREATE TABLE roster(id TEXT PRIMARY KEY, name TEXT NOT NULL, salt TEXT, verifier TEXT)');
        await db.execute('''CREATE TABLE messages(
          mid TEXT PRIMARY KEY, peer TEXT NOT NULL, outgoing INTEGER NOT NULL,
          kind TEXT NOT NULL, body TEXT, path TEXT, fname TEXT, size INTEGER,
          ts INTEGER NOT NULL, status INTEGER NOT NULL, unread INTEGER NOT NULL DEFAULT 0)''');
        await db.execute('CREATE INDEX idx_peer ON messages(peer, ts)');
      },
    );
  }

  // ---- key/value ----
  Future<String?> kv(String k) async {
    final r = await d.query('kv', where: 'k=?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['v'] as String?;
  }

  Future<void> setKv(String k, String v) async {
    await d.insert('kv', {'k': k, 'v': v},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delKv(String k) async {
    await d.delete('kv', where: 'k=?', whereArgs: [k]);
  }

  // ---- roster ----
  Future<List<Map<String, Object?>>> roster() => d.query('roster',
      columns: ['id', 'name'], orderBy: 'name COLLATE NOCASE');

  Future<Map<String, Object?>?> teacher(String id) async {
    final r = await d.query('roster', where: 'id=?', whereArgs: [id]);
    return r.isEmpty ? null : r.first;
  }

  Future<void> upsertTeacher(
      String id, String name, String? salt, String? verifier) async {
    await d.insert('roster',
        {'id': id, 'name': name, 'salt': salt, 'verifier': verifier},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeTeacher(String id) async {
    await d.delete('roster', where: 'id=?', whereArgs: [id]);
  }

  Future<void> applyRoster(List<dynamic> list) async {
    await d.transaction((t) async {
      final ids = <String>[];
      for (final e in list) {
        final id = e['id'] as String;
        final name = e['name'] as String;
        ids.add(id);
        final n = await t
            .update('roster', {'name': name}, where: 'id=?', whereArgs: [id]);
        if (n == 0) await t.insert('roster', {'id': id, 'name': name});
      }
      if (ids.isEmpty) {
        await t.delete('roster');
      } else {
        await t.delete('roster',
            where: 'id NOT IN (${List.filled(ids.length, '?').join(',')})',
            whereArgs: ids);
      }
    });
  }

  // ---- messages ----
  Future<bool> hasMsg(String mid) async =>
      (await d.query('messages', columns: ['mid'], where: 'mid=?', whereArgs: [mid]))
          .isNotEmpty;

  Future<Msg?> msg(String mid) async {
    final r = await d.query('messages', where: 'mid=?', whereArgs: [mid]);
    return r.isEmpty ? null : Msg.fromMap(r.first);
  }

  Future<void> insertMsg(Msg m) async {
    await d.insert('messages', m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> setStatus(String mid, int status) async {
    await d.update('messages', {'status': status},
        where: 'mid=?', whereArgs: [mid]);
  }

  Future<void> setFileDone(String mid, String path, int size) async {
    await d.update('messages', {'path': path, 'size': size, 'status': kSent},
        where: 'mid=?', whereArgs: [mid]);
  }

  Future<List<Msg>> messages(String peer) async => (await d.query('messages',
          where: 'peer=?', whereArgs: [peer], orderBy: 'ts ASC'))
      .map(Msg.fromMap)
      .toList();

  Future<List<Map<String, Object?>>> conversations() => d.rawQuery('''
    SELECT m.peer AS peer, m.kind AS kind, m.body AS body, m.fname AS fname,
           m.ts AS ts, m.outgoing AS outgoing, m.status AS status,
           (SELECT COUNT(*) FROM messages u WHERE u.peer=m.peer AND u.unread=1) AS unread
    FROM messages m
    WHERE m.ts=(SELECT MAX(ts) FROM messages x WHERE x.peer=m.peer)
    GROUP BY m.peer ORDER BY m.ts DESC''');

  Future<Set<String>> searchPeers(String q) async {
    final r = await d.rawQuery(
        'SELECT DISTINCT peer FROM messages WHERE body LIKE ? OR fname LIKE ?',
        ['%$q%', '%$q%']);
    return r.map((e) => e['peer'] as String).toSet();
  }

  Future<void> markRead(String peer) async {
    await d.update('messages', {'unread': 0},
        where: 'peer=? AND unread=1', whereArgs: [peer]);
  }

  Future<List<Msg>> outbox(String peer) async => (await d.query('messages',
          where:
              "peer=? AND outgoing=1 AND (status IN (0,3) OR (status=1 AND kind='text'))",
          whereArgs: [peer],
          orderBy: 'ts ASC'))
      .map(Msg.fromMap)
      .toList();

  Future<void> requeueSending(String peer) async {
    await d.update('messages', {'status': kQueued},
        where: 'peer=? AND outgoing=1 AND status=4', whereArgs: [peer]);
  }

  Future<void> clearChat(String peer) async {
    await d.delete('messages', where: 'peer=?', whereArgs: [peer]);
  }

  Future<void> clearAll() async {
    await d.delete('messages');
  }
}

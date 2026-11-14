const kQueued = 0, kSent = 1, kDelivered = 2, kFailed = 3, kSending = 4;

class Msg {
  final String mid, peer, kind; // kind: text | image | pdf
  final bool outgoing;
  String? body, path, fname;
  int size, ts, status;
  bool unread;
  Msg({
    required this.mid,
    required this.peer,
    required this.kind,
    required this.outgoing,
    this.body,
    this.path,
    this.fname,
    this.size = 0,
    required this.ts,
    required this.status,
    this.unread = false,
  });

  Map<String, Object?> toMap() => {
        'mid': mid,
        'peer': peer,
        'outgoing': outgoing ? 1 : 0,
        'kind': kind,
        'body': body,
        'path': path,
        'fname': fname,
        'size': size,
        'ts': ts,
        'status': status,
        'unread': unread ? 1 : 0,
      };

  factory Msg.fromMap(Map<String, Object?> m) => Msg(
        mid: m['mid'] as String,
        peer: m['peer'] as String,
        kind: m['kind'] as String,
        outgoing: m['outgoing'] == 1,
        body: m['body'] as String?,
        path: m['path'] as String?,
        fname: m['fname'] as String?,
        size: (m['size'] as int?) ?? 0,
        ts: m['ts'] as int,
        status: m['status'] as int,
        unread: m['unread'] == 1,
      );
}

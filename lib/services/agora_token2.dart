import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Generates Agora AccessToken2 (version "007") tokens.
/// Compatible with agora_rtc_engine 6.x which requires AccessToken2.
class AccessToken2Builder {
  static const String _version = '007';

  // Service types
  static const int _serviceRtc = 1;

  // RTC privileges
  static const int _privJoinChannel = 1;
  static const int _privPublishAudio = 2;
  static const int _privPublishVideo = 3;
  static const int _privPublishData = 4;

  /// Build an RTC token for joining a voice/video channel.
  ///
  /// [appId] - Agora App ID
  /// [appCertificate] - Agora App Certificate
  /// [channelName] - Channel name to join
  /// [uid] - User identifier (string). Use Firebase UID or "" for wildcard.
  /// [expireSeconds] - Token validity duration in seconds (default 24 hours)
  static String buildRtcToken({
    required String appId,
    required String appCertificate,
    required String channelName,
    required String uid,
    int expireSeconds = 86400,
  }) {
    final int issueTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final int salt = Random.secure().nextInt(99999999) + 1;

    // === Build signing key ===
    // signing = HMAC(key=pack(issue_ts), msg=app_certificate)
    // signing = HMAC(key=pack(salt), msg=signing)
    List<int> signing = _hmacSha256(_packUint32(issueTs), utf8.encode(appCertificate));
    signing = _hmacSha256(_packUint32(salt), signing);

    // === Build content ===
    final data = BytesBuilder();
    data.add(_packUint32(issueTs));
    data.add(_packUint32(salt));
    data.add(_packUint32(expireSeconds));

    // Pack services: 1 service (RTC)
    data.add(_packUint16(1)); // number of services
    data.add(_packUint16(_serviceRtc)); // service type = RTC

    // ServiceRtc.pack() = pack_string(channel) + pack_string(uid) + privileges
    data.add(_packString(channelName));
    data.add(_packString(uid));

    // Pack privileges map
    final Map<int, int> privileges = {
      _privJoinChannel: expireSeconds,
      _privPublishAudio: expireSeconds,
      _privPublishVideo: expireSeconds,
      _privPublishData: expireSeconds,
    };
    data.add(_packUint16(privileges.length));
    privileges.forEach((key, value) {
      data.add(_packUint16(key));
      data.add(_packUint32(value));
    });

    final contentBytes = Uint8List.fromList(data.toBytes());

    // === Sign content ===
    final signature = Uint8List.fromList(_hmacSha256(signing, contentBytes));

    // === Assemble final packet ===
    final res = BytesBuilder();
    res.add(_packString(appId)); // uint16 length + appId bytes
    res.add(_packUint32(signature.length));
    res.add(signature);
    res.add(_packUint32(contentBytes.length));
    res.add(contentBytes);

    // === Compress with zlib and base64 encode ===
    final compressed = ZLibEncoder().convert(res.toBytes());
    return _version + base64.encode(compressed);
  }

  // HMAC-SHA256: key=key, message=msg
  static List<int> _hmacSha256(List<int> key, List<int> msg) {
    return Hmac(sha256, key).convert(msg).bytes;
  }

  static Uint8List _packUint32(int value) {
    final bytes = ByteData(4);
    bytes.setUint32(0, value & 0xFFFFFFFF, Endian.little);
    return bytes.buffer.asUint8List();
  }

  static Uint8List _packUint16(int value) {
    final bytes = ByteData(2);
    bytes.setUint16(0, value & 0xFFFF, Endian.little);
    return bytes.buffer.asUint8List();
  }

  static Uint8List _packString(String s) {
    final encoded = utf8.encode(s);
    final result = BytesBuilder();
    result.add(_packUint16(encoded.length));
    result.add(encoded);
    return Uint8List.fromList(result.toBytes());
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// 同款设备推送协议 (v1)
///
/// 发现: 发送端 UDP 广播 `disc`，接收端应答 `hello`。
/// 推送: 发送端 TCP 发送 `push`，接收端应答 `ack`。
abstract final class CastProtocol {
  static const String appId = 'com.shaoy.piliplus';
  static const int version = 1;
  static const int tcpPort = 26980;
  static const int udpPort = 26981;
}

/// 局域网内一台可接收推送的设备
class CastDevice {
  final String name;
  final InternetAddress address;
  final int port;
  final int version;

  const CastDevice({
    required this.name,
    required this.address,
    required this.port,
    required this.version,
  });
}

/// 推送的视频信息；接收端凭标识用自己的账号重新拉流
class CastPushPayload {
  final String type; // 'ugc' | 'pgc'
  final String? bvid;
  final int? aid;
  final int cid;
  final int? epId;
  final int? seasonId;
  final int? pgcType;
  final String title;
  final String cover;
  final int positionSec;

  const CastPushPayload({
    required this.type,
    this.bvid,
    this.aid,
    required this.cid,
    this.epId,
    this.seasonId,
    this.pgcType,
    this.title = '',
    this.cover = '',
    this.positionSec = 0,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'bvid': bvid,
        'aid': aid,
        'cid': cid,
        'epId': epId,
        'seasonId': seasonId,
        'pgcType': pgcType,
        'title': title,
        'cover': cover,
        'positionSec': positionSec,
      };

  factory CastPushPayload.fromJson(Map<String, dynamic> json) =>
      CastPushPayload(
        type: json['type'] as String? ?? 'ugc',
        bvid: json['bvid'] as String?,
        aid: json['aid'] as int?,
        cid: json['cid'] as int? ?? 0,
        epId: json['epId'] as int?,
        seasonId: json['seasonId'] as int?,
        pgcType: json['pgcType'] as int?,
        title: json['title'] as String? ?? '',
        cover: json['cover'] as String? ?? '',
        positionSec: json['positionSec'] as int? ?? 0,
      );
}

/// 设备间消息（JSON 行协议，字段缩写以减小 UDP 包体积）
class CastMessage {
  final String type;
  final String? id;
  final int version;
  final String? app;
  final String? from;
  final String? name;
  final int? port;
  final CastPushPayload? payload;

  const CastMessage({
    required this.type,
    this.id,
    required this.version,
    this.app,
    this.from,
    this.name,
    this.port,
    this.payload,
  });

  factory CastMessage.disc() => const CastMessage(
        type: 'disc',
        version: CastProtocol.version,
        app: CastProtocol.appId,
      );

  factory CastMessage.hello({
    required String name,
    required int port,
  }) => CastMessage(
        type: 'hello',
        version: CastProtocol.version,
        app: CastProtocol.appId,
        name: name,
        port: port,
      );

  factory CastMessage.push({
    required String id,
    required String from,
    required CastPushPayload payload,
  }) => CastMessage(
        type: 'push',
        id: id,
        version: CastProtocol.version,
        app: CastProtocol.appId,
        from: from,
        payload: payload,
      );

  factory CastMessage.ack({String? id}) => CastMessage(
        type: 'ack',
        id: id,
        version: CastProtocol.version,
        app: CastProtocol.appId,
      );

  Map<String, dynamic> toJson() => {
        't': type,
        'id': id,
        'v': version,
        'app': app,
        'from': from,
        'name': name,
        'port': port,
        'payload': payload?.toJson(),
      };

  String toJsonString() => jsonEncode(toJson());

  static CastMessage? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return CastMessage(
        type: decoded['t'] as String? ?? '',
        id: decoded['id'] as String?,
        version: decoded['v'] as int? ?? 0,
        app: decoded['app'] as String?,
        from: decoded['from'] as String?,
        name: decoded['name'] as String?,
        port: decoded['port'] as int?,
        payload: decoded['payload'] is Map<String, dynamic>
            ? CastPushPayload.fromJson(
                decoded['payload'] as Map<String, dynamic>,
              )
            : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// 本机设备名（用于发现应答与推送来源展示）
abstract final class CastDeviceName {
  static String? _cached;

  static Future<String> get() async {
    final cached = _cached;
    if (cached != null) return cached;
    var name = Platform.localHostname;
    try {
      if (Platform.isAndroid) {
        name = (await DeviceInfoPlugin().androidInfo).model;
      } else if (Platform.isIOS) {
        name = (await DeviceInfoPlugin().iosInfo).model;
      }
    } catch (_) {}
    _cached = name.isEmpty ? 'PiliPlus' : name;
    return _cached!;
  }
}

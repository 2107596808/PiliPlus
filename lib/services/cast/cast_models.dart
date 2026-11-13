import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// 同款设备互联协议 (v2)
///
/// HTTP: 发送端用 `POST /push` 推送、`GET /ping` 探测设备信息。
/// WS:   `GET /ws` 升级成长连接，双向收发 `CastMessage`，承载配对、队列与同播。
/// UDP:  发送端广播 `disc`，接收端应答 `hello`（保留兼容旧版发现）。
abstract final class CastProtocol {
  static const String appId = 'com.shaoy.piliplus';
  static const int version = 2;

  /// 单端口：HTTP 推送与 WebSocket 长连接共用
  static const int port = 26982;

  /// v1 端口，仅用于兼容旧版本
  static const int legacyTcpPort = 26980;

  /// v1 协议号，旧版发送端仍在使用
  static const int legacyVersion = 1;
  static const int udpPort = 26981;

  static const String wsPath = '/ws';
  static const String pingPath = '/ping';
  static const String pushPath = '/push';
  static const String pairPath = '/pair';

  /// 配对后随请求携带的请求头
  static const String tokenHeader = 'x-piliplus-token';
}

/// 局域网内一台可接收推送的设备
class CastDevice {
  final String name;
  final InternetAddress address;
  final int port;
  final int version;

  /// 该设备是否已与本机配对
  final bool paired;

  const CastDevice({
    required this.name,
    required this.address,
    required this.port,
    required this.version,
    this.paired = false,
  });

  String get ip => address.address;

  Map<String, dynamic> toJson() => {
    'name': name,
    'ip': ip,
    'port': port,
    'v': version,
    'paired': paired,
  };
}

/// 推送内容：视频、通用链接、队列或同播控制
sealed class CastPayload {
  const CastPayload();

  Map<String, dynamic> toJson();

  static CastPayload? fromJson(Map<String, dynamic> json) {
    return switch (json['kind'] as String? ?? 'video') {
      'video' => CastVideoPayload.fromJson(json),
      'link' => CastLinkPayload.fromJson(json),
      'queue' => CastQueuePayload.fromJson(json),
      'sync' => CastSyncPayload.fromJson(json),
      _ => null,
    };
  }
}

/// 推送的视频信息；接收端凭标识用自己的账号重新拉流
class CastVideoPayload extends CastPayload {
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

  const CastVideoPayload({
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

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'video',
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

  factory CastVideoPayload.fromJson(Map<String, dynamic> json) =>
      CastVideoPayload(
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

/// 通用链接：动态、专栏、直播间、收藏夹等，交给接收端按自家路由打开
class CastLinkPayload extends CastPayload {
  final String url;
  final String title;

  const CastLinkPayload({required this.url, this.title = ''});

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'link',
    'url': url,
    'title': title,
  };

  factory CastLinkPayload.fromJson(Map<String, dynamic> json) =>
      CastLinkPayload(
        url: json['url'] as String? ?? '',
        title: json['title'] as String? ?? '',
      );
}

/// 队列推送：收藏夹、稍后再看等整批下发
class CastQueuePayload extends CastPayload {
  final String title;
  final List<CastVideoPayload> items;

  const CastQueuePayload({required this.title, required this.items});

  int get length => items.length;

  CastVideoPayload? get first => items.isEmpty ? null : items.first;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'queue',
    'title': title,
    'items': items.map((item) => item.toJson()).toList(),
  };

  factory CastQueuePayload.fromJson(Map<String, dynamic> json) =>
      CastQueuePayload(
        title: json['title'] as String? ?? '',
        items: (json['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CastVideoPayload.fromJson)
            .toList(),
      );
}

/// 一起看：播放状态同步
class CastSyncPayload extends CastPayload {
  final String action; // 'play' | 'pause' | 'seek' | 'progress'
  final int positionSec;

  const CastSyncPayload({required this.action, this.positionSec = 0});

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'sync',
    'action': action,
    'positionSec': positionSec,
  };

  factory CastSyncPayload.fromJson(Map<String, dynamic> json) =>
      CastSyncPayload(
        action: json['action'] as String? ?? 'progress',
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
  final CastPayload? payload;

  /// 配对令牌：接收端下发的凭据，或发送端本次出示的凭据
  final String? token;

  /// 配对码：接收端屏幕显示的四位数字，发送端回填
  final String? code;

  const CastMessage({
    required this.type,
    this.id,
    required this.version,
    this.app,
    this.from,
    this.name,
    this.port,
    this.payload,
    this.token,
    this.code,
  });

  factory CastMessage.disc() => const CastMessage(
    type: 'disc',
    version: CastProtocol.version,
    app: CastProtocol.appId,
  );

  factory CastMessage.hello({
    required String name,
    required int port,
    bool paired = false,
  }) => CastMessage(
    type: 'hello',
    version: CastProtocol.version,
    app: CastProtocol.appId,
    name: name,
    port: port,
    token: paired ? '1' : null,
  );

  /// 请求配对：发送端先要一个配对码
  factory CastMessage.pairRequest({required String id, required String from}) =>
      CastMessage(
        type: 'pair_request',
        id: id,
        version: CastProtocol.version,
        app: CastProtocol.appId,
        from: from,
      );

  /// 提交配对码换令牌，或使用已有令牌直接握手
  factory CastMessage.pairSubmit({
    required String id,
    required String from,
    String? code,
    String? token,
  }) => CastMessage(
    type: 'pair_submit',
    id: id,
    version: CastProtocol.version,
    app: CastProtocol.appId,
    from: from,
    code: code,
    token: token,
  );

  factory CastMessage.paired({
    String? id,
    required String token,
    required String name,
  }) => CastMessage(
    type: 'paired',
    id: id,
    version: CastProtocol.version,
    app: CastProtocol.appId,
    name: name,
    token: token,
  );

  factory CastMessage.push({
    required String id,
    required String from,
    required CastPayload payload,
  }) => CastMessage(
    type: 'push',
    id: id,
    version: CastProtocol.version,
    app: CastProtocol.appId,
    from: from,
    payload: payload,
  );

  factory CastMessage.sync({
    required String from,
    required CastSyncPayload payload,
  }) => CastMessage(
    type: 'sync',
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

  factory CastMessage.error({String? id, required String reason}) =>
      CastMessage(
        type: 'error',
        id: id,
        version: CastProtocol.version,
        app: CastProtocol.appId,
        name: reason,
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
    'token': token,
    'code': code,
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
            ? CastPayload.fromJson(decoded['payload'] as Map<String, dynamic>)
            : null,
        token: decoded['token'] as String?,
        code: decoded['code'] as String?,
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

/// 本机局域网地址（用于设置页展示与二维码）
abstract final class CastLocalAddress {
  static Future<List<String>> list() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      return interfaces
          .expand((iface) => iface.addresses)
          .map((address) => address.address)
          .where((ip) => !ip.startsWith('169.254.'))
          .toSet()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 优先返回私有网段地址
  static Future<String?> primary() async {
    final list = await CastLocalAddress.list();
    for (final ip in list) {
      if (ip.startsWith('192.168.') ||
          ip.startsWith('10.') ||
          RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) {
        return ip;
      }
    }
    return list.isEmpty ? null : list.first;
  }
}

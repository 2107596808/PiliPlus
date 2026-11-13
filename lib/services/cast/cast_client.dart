import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/cast/cast_models.dart';
import 'package:PiliPlus/services/cast/cast_pairing.dart';
import 'package:uuid/v4.dart';

/// 发送端：推送、配对与同播长连接
abstract final class CastClient {
  /// 使用已保存的令牌推送；未配对时回退到旧版无认证请求
  static Future<bool> push(
    CastDevice device,
    CastPayload payload, {
    required String from,
  }) async {
    final token = CastPairing.tokenFor(device.ip);
    final ok = await _post(device, payload, from: from, token: token);
    if (ok) return true;
    // 令牌失效（对方重置过），清掉后按未配对再试一次
    if (token != null) {
      await CastPairing.forget(device.ip);
      return _post(device, payload, from: from);
    }
    return false;
  }

  static Future<bool> _post(
    CastDevice device,
    CastPayload payload, {
    required String from,
    String? token,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..idleTimeout = const Duration(seconds: 5);
      final request = await client.postUrl(
        Uri.parse(
          'http://${device.ip}:${device.port}${CastProtocol.pushPath}',
        ),
      );
      request.headers.contentType = ContentType.json;
      if (token != null) {
        request.headers.set(CastProtocol.tokenHeader, token);
      }
      request.write(
        CastMessage.push(
          id: const UuidV4().generate(),
          from: from,
          payload: payload,
        ).toJsonString(),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) return false;
      final msg = CastMessage.tryParse(body);
      return msg?.type == 'ack';
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  /// 配对：请对方亮出配对码，本机回填确认
  ///
  /// 返回 true 表示对方已进入配对状态并在自己的界面上展示了配对码。
  static Future<bool> requestPair(CastDevice device, String from) async {
    final body = await _pair(
      device,
      CastMessage.pairRequest(
        id: const UuidV4().generate(),
        from: from,
      ).toJsonString(),
    );
    return body?['ok'] == true;
  }

  static Future<String?> submitPairCode(
    CastDevice device,
    String code,
    String from,
  ) async {
    final body = await _pair(
      device,
      CastMessage.pairSubmit(
        id: const UuidV4().generate(),
        from: from,
        code: code,
      ).toJsonString(),
    );
    final token = body?['token'] as String?;
    if (token != null && token.isNotEmpty) {
      await CastPairing.saveToken(device.ip, token);
      return token;
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _pair(
    CastDevice device,
    String body,
  ) async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..idleTimeout = const Duration(seconds: 5);
      final request = await client.postUrl(
        Uri.parse(
          'http://${device.ip}:${device.port}${CastProtocol.pairPath}',
        ),
      );
      request.headers.contentType = ContentType.json;
      request.write(body);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) return null;
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// 同播：与某台设备建立长连接
  static Future<CastSyncSession?> connect(
    CastDevice device, {
    required String from,
    void Function(CastSyncPayload payload)? onSync,
  }) async {
    try {
      final token = CastPairing.tokenFor(device.ip);
      final ws = await WebSocket.connect(
        'ws://${device.ip}:${device.port}${CastProtocol.wsPath}',
        headers: token == null ? null : {CastProtocol.tokenHeader: token},
      ).timeout(const Duration(seconds: 5));
      final session = CastSyncSession._(ws, from, device);
      session._subscribe(onSync);
      ws.add(
        CastMessage(
          type: 'hello',
          version: CastProtocol.version,
          app: CastProtocol.appId,
          from: from,
          name: from,
        ).toJsonString(),
      );
      return session;
    } catch (_) {
      return null;
    }
  }
}

/// 一起看：与一台设备保持的长连接
class CastSyncSession {
  CastSyncSession._(this._ws, this.from, this.device);

  final WebSocket _ws;
  final String from;
  final CastDevice device;
  void Function(CastSyncPayload payload)? _onSync;

  bool get closed => _ws.readyState == WebSocket.closed;

  void _subscribe(void Function(CastSyncPayload payload)? onSync) {
    _onSync = onSync;
    _ws.listen(
      (data) {
        final msg = CastMessage.tryParse(
          data is String
              ? data
              : utf8.decode(data as List<int>, allowMalformed: true),
        );
        final payload = msg?.payload;
        if (payload is CastSyncPayload) _onSync?.call(payload);
      },
      onDone: () => _onSync = null,
      onError: (_) => _onSync = null,
      cancelOnError: true,
    );
  }

  void send(CastSyncPayload payload) {
    if (closed) return;
    try {
      _ws.add(CastMessage.sync(from: from, payload: payload).toJsonString());
    } catch (_) {}
  }

  Future<void> close() async {
    try {
      await _ws.close();
    } catch (_) {}
  }
}

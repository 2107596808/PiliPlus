import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/cast/cast_models.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// 接收端：常驻 TCP 监听与 UDP 发现应答
class CastListener {
  CastListener._();

  static final CastListener instance = CastListener._();

  ServerSocket? _tcpServer;
  RawDatagramSocket? _udp;
  HttpServer? _httpServer;
  bool _started = false;

  /// 收到推送后的回调，参数为推送内容与发送端设备名
  void Function(CastPushPayload payload, String from)? onPush;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await Future.wait([_startTcp(), _startUdp(), _startHttp()]);
  }

  Future<void> stop() async {
    _started = false;
    await _tcpServer?.close();
    _tcpServer = null;
    _udp?.close();
    _udp = null;
    await _httpServer?.close();
    _httpServer = null;
  }

  Future<void> _startTcp() async {
    try {
      _tcpServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        CastProtocol.tcpPort,
      );
      _tcpServer!.listen(_handleConnection, onError: _logError);
    } catch (e) {
      _started = false;
      logger.w('CastListener: TCP 监听启动失败 $e');
    }
  }

  Future<void> _startUdp() async {
    try {
      _udp = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        CastProtocol.udpPort,
        reuseAddress: true,
      );
      _udp!.listen(_onUdpEvent, onError: _logError);
    } catch (e) {
      _started = false;
      logger.w('CastListener: UDP 监听启动失败 $e');
    }
  }

  Future<void> _startHttp() async {
    try {
      _httpServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        CastProtocol.httpPort,
      );
      _httpServer!.listen(_onHttpRequest, onError: _logError);
    } catch (e) {
      _started = false;
      logger.w('CastListener: HTTP 监听启动失败 $e');
    }
  }

  void _onHttpRequest(HttpRequest request) {
    final response = request.response;
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type');
    if (request.method == 'OPTIONS') {
      response
        ..statusCode = HttpStatus.noContent
        ..close();
      return;
    }
    if (request.method == 'GET' && request.uri.path == '/ping') {
      _handlePing(response);
      return;
    }
    if (request.method == 'POST' && request.uri.path == '/push') {
      _handlePush(request, response);
      return;
    }
    response
      ..statusCode = HttpStatus.notFound
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'error': 'not found'}))
      ..close();
  }

  void _handlePing(HttpResponse response) {
    CastDeviceName.get().then((name) {
      response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'ok': true,
            'name': name,
            'app': CastProtocol.appId,
            'v': CastProtocol.version,
            'receiving': Pref.enableCastReceive,
          }),
        )
        ..close();
    });
  }

  Future<void> _handlePush(
    HttpRequest request,
    HttpResponse response,
  ) async {
    final body = await utf8.decoder.bind(request).join();
    final msg = CastMessage.tryParse(body);
    final payload = msg?.payload;
    if (msg == null || msg.type != 'push' || !_isValid(msg)) {
      _httpBadRequest(response, 'invalid message');
      return;
    }
    if (payload == null || payload.cid <= 0) {
      _httpBadRequest(response, 'invalid payload');
      return;
    }
    if (!Pref.enableCastReceive) {
      response
        ..statusCode = HttpStatus.serviceUnavailable
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'cast receive disabled'}))
        ..close();
      return;
    }
    response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(CastMessage.ack(id: msg.id).toJson()))
      ..close();
    onPush?.call(payload, msg.from ?? '');
  }

  void _httpBadRequest(HttpResponse response, String error) {
    response
      ..statusCode = HttpStatus.badRequest
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'error': error}))
      ..close();
  }

  void _onUdpEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _udp?.receive();
    if (datagram == null) return;
    final msg = CastMessage.tryParse(
      utf8.decode(datagram.data, allowMalformed: true),
    );
    if (msg == null || msg.type != 'disc' || !_isValid(msg)) return;
    if (!Pref.enableCastReceive) return;
    CastDeviceName.get().then((name) {
      _udp?.send(
        utf8.encode(
          CastMessage.hello(
            name: name,
            port: CastProtocol.tcpPort,
          ).toJsonString(),
        ),
        datagram.address,
        datagram.port,
      );
    });
  }

  void _handleConnection(Socket socket) {
    final buffer = StringBuffer();
    socket.listen(
      (data) {
        buffer.write(utf8.decode(data, allowMalformed: true));
        final text = buffer.toString();
        final index = text.indexOf('\n');
        if (index < 0) return;
        final msg = CastMessage.tryParse(text.substring(0, index));
        buffer.clear();
        if (index < text.length - 1) {
          buffer.write(text.substring(index + 1));
        }
        if (msg == null || msg.type != 'push' || !_isValid(msg)) return;
        final payload = msg.payload;
        if (payload == null || payload.cid <= 0) return;
        socket.write('${CastMessage.ack(id: msg.id).toJsonString()}\n');
        onPush?.call(payload, msg.from ?? '');
      },
      onError: (_) => socket.destroy(),
      onDone: socket.destroy,
    );
  }

  bool _isValid(CastMessage msg) =>
      msg.app == CastProtocol.appId && msg.version == CastProtocol.version;

  void _logError(Object e) => logger.w('CastListener: $e');
}

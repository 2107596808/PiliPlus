import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/cast/cast_models.dart';
import 'package:PiliPlus/services/cast/cast_pairing.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// 接收端：单端口 HTTP 推送 + WebSocket 长连接 + UDP 发现应答
class CastListener {
  CastListener._();

  static final CastListener instance = CastListener._();

  HttpServer? _httpServer;
  ServerSocket? _legacy;
  RawDatagramSocket? _udp;
  bool _started = false;

  final Set<WebSocket> _clients = {};

  /// 待确认的配对：配对码 -> 发起时间
  final Map<String, DateTime> _pendingCodes = {};

  /// 收到推送
  void Function(CastPayload payload, String from)? onPush;

  /// 收到同播控制
  void Function(CastSyncPayload payload, String from)? onSync;

  /// 有设备请求配对，需要界面展示配对码并等待用户确认
  void Function(String from, String code)? onPairRequest;

  /// 已连接的外部设备名变化
  void Function(List<String> names)? onPeersChanged;

  bool get isRunning => _started;

  List<String> get peers => _clients.map((ws) => _peerName(ws)).toList();

  final Map<WebSocket, String> _peerNames = {};

  String _peerName(WebSocket ws) => _peerNames[ws] ?? '设备';

  /// 启动监听；主端口（HTTP+WS）起不来就整体回滚并返回 false
  Future<bool> start() async {
    if (_started) return true;
    final httpOk = await _startHttp();
    if (!httpOk) {
      _started = false;
      return false;
    }
    _started = true;
    // 兼容通道失败不影响主流程
    await Future.wait([_startUdp(), _startLegacyTcp()]);
    return true;
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> stop() async {
    _started = false;
    for (final ws in _clients.toList()) {
      try {
        await ws.close();
      } catch (_) {}
    }
    _clients.clear();
    _peerNames.clear();
    _pendingCodes.clear();
    await _httpServer?.close(force: true);
    _httpServer = null;
    await _legacy?.close();
    _legacy = null;
    _udp?.close();
    _udp = null;
  }

  /// 旧版发送端（v1）走 26980 的换行分隔 JSON 流，只收推送
  Future<void> _startLegacyTcp() async {
    try {
      _legacy = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        CastProtocol.legacyTcpPort,
        shared: true,
      );
      _legacy!.listen(_onLegacyConnection, onError: _logError);
    } catch (e) {
      logger.w('CastListener: 旧版端口启动失败 $e');
    }
  }

  void _onLegacyConnection(Socket socket) {
    if (!_isLocal(socket.remoteAddress)) {
      socket.destroy();
      return;
    }
    final buffer = StringBuffer();
    socket.listen(
      (data) {
        buffer.write(utf8.decode(data, allowMalformed: true));
        final text = buffer.toString();
        final index = text.indexOf('\n');
        if (index < 0) return;
        buffer.clear();
        final line = text.substring(0, index).trim();
        final rest = text.substring(index + 1);
        if (rest.isNotEmpty) buffer.write(rest);
        final msg = CastMessage.tryParse(line);
        if (msg == null || !_isValid(msg)) return;
        if (msg.type != 'push' || !Pref.enableCastReceive) return;
        final payload = msg.payload;
        if (!_validPayload(payload)) return;
        try {
          socket.write(CastMessage.ack(id: msg.id).toJsonString() + '\n');
        } catch (_) {}
        _dispatch(payload!, msg.from ?? '');
      },
      onError: (_) => socket.destroy(),
      cancelOnError: true,
    );
  }

  Future<bool> _startHttp() async {
    try {
      _httpServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        CastProtocol.port,
        shared: false,
      );
      _httpServer!.listen(_onHttpRequest, onError: _logError);
      return true;
    } catch (e) {
      logger.w('CastListener: HTTP 监听启动失败 $e');
      return false;
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
      logger.w('CastListener: UDP 监听启动失败 $e');
    }
  }

  void _onHttpRequest(HttpRequest request) {
    final response = request.response;
    // 仅允许局域网来源；CORS 仍放开以支持浏览器扩展
    if (!_isLocal(request.connectionInfo?.remoteAddress)) {
      response
        ..statusCode = HttpStatus.forbidden
        ..close();
      return;
    }
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set(
        'Access-Control-Allow-Headers',
        'Content-Type, ${CastProtocol.tokenHeader}',
      );
    if (request.method == 'OPTIONS') {
      response
        ..statusCode = HttpStatus.noContent
        ..close();
      return;
    }
    final path = request.uri.path;
    if (path == CastProtocol.wsPath &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      _handleUpgrade(request);
      return;
    }
    if (request.method == 'GET' && path == CastProtocol.pingPath) {
      _handlePing(response);
      return;
    }
    if (request.method == 'POST' && path == CastProtocol.pushPath) {
      _handleHttpPush(request);
      return;
    }
    if (request.method == 'POST' && path == CastProtocol.pairPath) {
      _handlePairRequest(request);
      return;
    }
    response
      ..statusCode = HttpStatus.notFound
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'error': 'not found'}))
      ..close();
  }

  bool _isLocal(InternetAddress? address) {
    if (address == null) return true; // 部分平台拿不到来源，放行交给 token 校验
    final ip = address.address;
    return address.isLoopback ||
        ip.startsWith('192.168.') ||
        ip.startsWith('10.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip) ||
        ip.startsWith('169.254.');
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
            'port': CastProtocol.port,
            'receiving': Pref.enableCastReceive,
            'paired': CastPairing.paired,
            'sync': Pref.enableCastSync,
            'ws': CastProtocol.wsPath,
          }),
        )
        ..close();
    });
  }

  /// 配对：{ code } 校验配对码，{ token } 校验已有令牌
  Future<void> _handlePairRequest(HttpRequest request) async {
    final response = request.response;
    final body = await utf8.decoder.bind(request).join();
    final msg = CastMessage.tryParse(body);
    if (msg == null ||
        msg.app != CastProtocol.appId ||
        msg.version != CastProtocol.version) {
      _json(response, HttpStatus.badRequest, {'error': 'invalid message'});
      return;
    }
    if (msg.token != null && msg.token!.isNotEmpty) {
      final ok = msg.token == CastPairing.token;
      _json(response, ok ? HttpStatus.ok : HttpStatus.forbidden, {
        'ok': ok,
        'token': ok ? CastPairing.token : null,
      });
      return;
    }
    // 请求配对码：码只在本机展示，不随响应回传，避免同网段直接冒充
    if (msg.code == null || msg.code!.isEmpty) {
      final code = CastPairing.newCode();
      _pendingCodes[code] = DateTime.now();
      final from = msg.from ?? '';
      onPairRequest?.call(from, code);
      _json(response, HttpStatus.ok, {'ok': true, 'pending': true});
      return;
    }
    // 回填配对码
    final issued = _pendingCodes.remove(msg.code);
    final valid =
        issued != null &&
        DateTime.now().difference(issued) < const Duration(minutes: 5);
    if (!valid) {
      _json(response, HttpStatus.forbidden, {'error': 'invalid code'});
      return;
    }
    await CastPairing.addPeer(msg.from ?? '');
    _json(response, HttpStatus.ok, {
      'ok': true,
      'token': CastPairing.token,
      'name': await CastDeviceName.get(),
    });
  }

  Future<void> _handleHttpPush(HttpRequest request) async {
    final response = request.response;
    final body = await utf8.decoder.bind(request).join();
    final msg = CastMessage.tryParse(body);
    if (!_accepts(msg)) {
      _json(response, HttpStatus.forbidden, {'error': 'not paired'});
      return;
    }
    if (!Pref.enableCastReceive) {
      _json(response, HttpStatus.serviceUnavailable, {
        'error': 'cast receive disabled',
      });
      return;
    }
    final payload = msg!.payload;
    if (!_validPayload(payload)) {
      _json(response, HttpStatus.badRequest, {'error': 'invalid payload'});
      return;
    }
    _json(response, HttpStatus.ok, CastMessage.ack(id: msg.id).toJson());
    _dispatch(payload!, msg.from ?? '');
  }

  void _handleUpgrade(HttpRequest request) {
    // 已配对后，长连接必须带正确令牌，否则未配对设备也能控制本机播放
    final token =
        request.headers.value(CastProtocol.tokenHeader) ??
        request.uri.queryParameters['token'];
    if (!_tokenAccepted(token)) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write('not paired')
        ..close();
      return;
    }
    WebSocketTransformer.upgrade(request)
        .then((ws) {
          _clients.add(ws);
          ws.listen(
            (data) => _onSocketMessage(ws, data),
            onDone: () => _dropClient(ws),
            onError: (_) => _dropClient(ws),
            cancelOnError: true,
          );
          // 首个 hello 用于登记名称，不强制
          ws.add(
            CastMessage.hello(name: '', port: CastProtocol.port).toJsonString(),
          );
        })
        .catchError((Object e) {
          _logError(e);
        });
  }

  void _dropClient(WebSocket ws) {
    _clients.remove(ws);
    _peerNames.remove(ws);
    onPeersChanged?.call(peers);
  }

  void _onSocketMessage(WebSocket ws, dynamic data) {
    final text = data is String
        ? data
        : utf8.decode(data as List<int>, allowMalformed: true);
    final msg = CastMessage.tryParse(text);
    if (msg == null) return;
    if (msg.type == 'hello') {
      _peerNames[ws] = msg.from ?? msg.name ?? '设备';
      onPeersChanged?.call(peers);
      ws.add(CastMessage.ack().toJsonString());
      return;
    }
    if (msg.type == 'sync') {
      final payload = msg.payload;
      if (payload is CastSyncPayload && Pref.enableCastSync) {
        onSync?.call(payload, msg.from ?? '');
      }
      return;
    }
    if (msg.type != 'push') {
      ws.add(CastMessage.ack(id: msg.id).toJsonString());
      return;
    }
    if (!_accepts(msg)) {
      ws.add(
        CastMessage.error(id: msg.id, reason: 'not paired').toJsonString(),
      );
      return;
    }
    if (!Pref.enableCastReceive) {
      ws.add(
        CastMessage.error(
          id: msg.id,
          reason: 'cast receive disabled',
        ).toJsonString(),
      );
      return;
    }
    final payload = msg.payload;
    if (!_validPayload(payload)) {
      ws.add(
        CastMessage.error(id: msg.id, reason: 'invalid payload').toJsonString(),
      );
      return;
    }
    ws.add(CastMessage.ack(id: msg.id).toJsonString());
    _dispatch(payload!, msg.from ?? '');
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
          CastMessage.hello(name: name, port: CastProtocol.port).toJsonString(),
        ),
        datagram.address,
        datagram.port,
      );
    });
  }

  /// 已配对或本机为信任模式时接受；未配对则要求走 /pair
  bool _accepts(CastMessage? msg) {
    if (msg == null) return false;
    if (!_isValid(msg)) return false;
    return _tokenAccepted(msg.token);
  }

  bool _tokenAccepted(String? token) {
    if (!CastPairing.paired) return true; // 从未配对过，保持旧版零配置体验
    return token != null && token == CastPairing.token;
  }

  /// 兼容 v1 发送端（旧版浏览器扩展/组件），v1 只在 TCP 26980 上出现
  bool _isValid(CastMessage msg) =>
      msg.app == CastProtocol.appId &&
      (msg.version == CastProtocol.version ||
          msg.version == CastProtocol.legacyVersion);

  bool _validPayload(CastPayload? payload) {
    return switch (payload) {
      CastVideoPayload(:final cid) => cid > 0,
      CastLinkPayload(:final url) => url.isNotEmpty,
      CastQueuePayload(:final items) => items.isNotEmpty,
      CastSyncPayload() => true,
      null => false,
    };
  }

  void _dispatch(CastPayload payload, String from) {
    if (payload is CastSyncPayload) {
      onSync?.call(payload, from);
      return;
    }
    try {
      onPush?.call(payload, from);
    } catch (e) {
      logger.w('CastListener: 推送处理失败 $e');
    }
  }

  void _json(HttpResponse response, int status, Map<String, dynamic> body) {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body))
      ..close();
  }

  /// 向所有已连接设备广播同播状态
  void broadcastSync(CastSyncPayload payload) {
    final text = CastMessage.sync(from: 'me', payload: payload).toJsonString();
    for (final ws in _clients) {
      try {
        ws.add(text);
      } catch (_) {}
    }
  }

  void _logError(Object e) => logger.w('CastListener: $e');
}

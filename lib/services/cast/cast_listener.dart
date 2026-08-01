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
  bool _started = false;

  /// 收到推送后的回调，参数为推送内容与发送端设备名
  void Function(CastPushPayload payload, String from)? onPush;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await Future.wait([_startTcp(), _startUdp()]);
  }

  Future<void> stop() async {
    _started = false;
    await _tcpServer?.close();
    _tcpServer = null;
    _udp?.close();
    _udp = null;
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

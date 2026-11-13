import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/cast/cast_models.dart';
import 'package:PiliPlus/services/cast/cast_pairing.dart';

/// 发送端：发现同网段设备
///
/// 先向广播地址发 `disc`；若没有应答，退化为按网段逐个探测 `GET /ping`，
/// 以覆盖不转发定向广播的路由器与 AP 隔离场景。
abstract final class CastDiscovery {
  static Future<List<CastDevice>> discover({
    Duration timeout = const Duration(seconds: 3),
    bool sweep = true,
  }) async {
    final found = await _broadcast(timeout: timeout);
    // 最近连过的设备优先补进来，避免广播被路由器拦截后列表为空
    final recent = await Future.wait(
      CastPairing.recentIps.map((ip) => probe(ip)),
    );
    for (final device in recent) {
      if (device != null) found.putIfAbsent(device.ip, () => device);
    }
    if (found.isNotEmpty || !sweep) return found.values.toList();
    final swept = await _sweep();
    for (final entry in swept.entries) {
      found.putIfAbsent(entry.key, () => entry.value);
    }
    return found.values.toList();
  }

  /// 直接探测某个 IP 或主机名，用于手动添加设备
  static Future<CastDevice?> probe(String host) async {
    final name = host.trim();
    if (name.isEmpty) return null;
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3)
        ..idleTimeout = const Duration(seconds: 3);
      final request = await client.getUrl(
        Uri.parse('http://$name:${CastProtocol.port}${CastProtocol.pingPath}'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      final text = await response.transform(utf8.decoder).join();
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return null;
      if (json['app'] != CastProtocol.appId || json['receiving'] != true) {
        return null;
      }
      final addresses = await InternetAddress.lookup(name);
      if (addresses.isEmpty) return null;
      return CastDevice(
        name: json['name'] as String? ?? name,
        address: addresses.first,
        port: json['port'] as int? ?? CastProtocol.port,
        version: json['v'] as int? ?? CastProtocol.version,
        paired: CastPairing.tokenFor(addresses.first.address) != null,
      );
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  static Future<Map<String, CastDevice>> _broadcast({
    required Duration timeout,
  }) async {
    final localAddresses =
        (await NetworkInterface.list(
              includeLoopback: false,
              type: InternetAddressType.IPv4,
            ))
            .map((iface) => iface.addresses)
            .expand((addresses) => addresses)
            .map((address) => address.address)
            .toSet();
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
    );
    socket.broadcastEnabled = true;
    final devices = <String, CastDevice>{};
    final packet = utf8.encode(CastMessage.disc().toJsonString());
    void sendDisc() {
      try {
        socket.send(
          packet,
          InternetAddress('255.255.255.255'),
          CastProtocol.udpPort,
        );
      } catch (_) {}
    }

    socket..listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      final msg = CastMessage.tryParse(
        utf8.decode(datagram.data, allowMalformed: true),
      );
      if (msg == null || msg.type != 'hello') return;
      if (msg.app != CastProtocol.appId) return;
      if (localAddresses.contains(datagram.address.address)) return;
      final name = (msg.name?.isNotEmpty ?? false)
          ? msg.name!
          : datagram.address.address;
      devices[datagram.address.address] = CastDevice(
        name: name,
        address: datagram.address,
        port: msg.port ?? CastProtocol.port,
        version: msg.version,
        paired: CastPairing.tokenFor(datagram.address.address) != null,
      );
    });
    sendDisc();
    // 广播可能丢包，重发两次
    final retry = Timer.periodic(const Duration(milliseconds: 700), (timer) {
      if (timer.tick >= 2) timer.cancel();
      sendDisc();
    });
    await Future<void>.delayed(timeout);
    retry.cancel();
    socket.close();
    return devices;
  }

  /// 子网扫描兜底：对每个本机所在 /24 逐个 ping
  static Future<Map<String, CastDevice>> _sweep() async {
    final devices = <String, CastDevice>{};
    final prefixes =
        (await NetworkInterface.list(
              includeLoopback: false,
              type: InternetAddressType.IPv4,
            ))
            .map((iface) => iface.addresses)
            .expand((addresses) => addresses)
            .map((address) => address.address)
            .where(
              (ip) =>
                  ip.startsWith('192.168.') ||
                  ip.startsWith('10.') ||
                  RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip),
            )
            .map((ip) => ip.substring(0, ip.lastIndexOf('.')))
            .toSet();
    for (final prefix in prefixes) {
      for (var i = 1; i < 255; i++) {
        final host = '$prefix.$i';
        unawaited(
          probe(host).then((device) {
            if (device != null) devices[device.ip] = device;
          }),
        );
      }
    }
    // 给扫描留出时间：并发探测，最多等 4 秒
    await Future<void>.delayed(const Duration(seconds: 4));
    return devices;
  }
}

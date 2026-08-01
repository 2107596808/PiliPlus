import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/cast/cast_models.dart';

/// 发送端：UDP 广播发现同网段设备
abstract final class CastDiscovery {
  static Future<List<CastDevice>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final localAddresses = (await NetworkInterface.list(
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
    socket
      ..listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final msg = CastMessage.tryParse(
          utf8.decode(datagram.data, allowMalformed: true),
        );
        if (msg == null ||
            msg.type != 'hello' ||
            msg.app != CastProtocol.appId ||
            msg.version != CastProtocol.version) {
          return;
        }
        if (localAddresses.contains(datagram.address.address)) return;
        final name = (msg.name?.isNotEmpty ?? false)
            ? msg.name!
            : datagram.address.address;
        devices[datagram.address.address] = CastDevice(
          name: name,
          address: datagram.address,
          port: msg.port ?? CastProtocol.tcpPort,
          version: msg.version,
        );
      })
      ..send(
        utf8.encode(CastMessage.disc().toJsonString()),
        InternetAddress('255.255.255.255'),
        CastProtocol.udpPort,
      );
    await Future<void>.delayed(timeout);
    socket.close();
    return devices.values.toList();
  }
}

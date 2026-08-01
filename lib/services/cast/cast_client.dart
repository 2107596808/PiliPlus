import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/cast/cast_models.dart';
import 'package:uuid/v4.dart';

/// 发送端：向指定设备推送播放信息
abstract final class CastClient {
  static Future<bool> push(
    CastDevice device,
    CastPushPayload payload, {
    required String from,
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        device.address,
        device.port,
        timeout: const Duration(seconds: 5),
      );
      final id = const UuidV4().generate();
      socket.write(
        '${CastMessage.push(id: id, from: from, payload: payload).toJsonString()}\n',
      );
      await socket.flush();
      final completer = Completer<bool>();
      final timer = Timer(const Duration(seconds: 5), () {
        if (!completer.isCompleted) completer.complete(false);
      });
      socket.listen((data) {
        final msg = CastMessage.tryParse(
          utf8.decode(data, allowMalformed: true),
        );
        if (msg != null &&
            msg.type == 'ack' &&
            msg.id == id &&
            !completer.isCompleted) {
          completer.complete(true);
        }
      });
      final ok = await completer.future;
      timer.cancel();
      return ok;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }
}

import 'dart:convert';
import 'dart:math';

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';

/// 配对凭据：本机作为接收端时下发给发送端的令牌
abstract final class CastPairing {
  /// 本机固定令牌，首次使用时生成并持久化
  static String get token {
    final saved = GStorage.setting.get(SettingBoxKey.castToken);
    if (saved is String && saved.isNotEmpty) return saved;
    final generated = _randomToken();
    GStorage.setting.put(SettingBoxKey.castToken, generated);
    return generated;
  }

  static bool get paired =>
      (GStorage.setting.get(SettingBoxKey.castToken) as String?)?.isNotEmpty ??
      false;

  /// 已配对的发送端名称，用于设置页展示与解绑
  static List<String> get peers {
    final saved = GStorage.setting.get(SettingBoxKey.castPeers);
    if (saved is! String || saved.isEmpty) return const [];
    try {
      return (jsonDecode(saved) as List<dynamic>).whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> addPeer(String from) async {
    final name = from.isEmpty ? '未知设备' : from;
    final list = [...peers];
    if (!list.contains(name)) list.add(name);
    await GStorage.setting.put(SettingBoxKey.castPeers, jsonEncode(list));
  }

  static Future<void> clear() async {
    await GStorage.setting.delete(SettingBoxKey.castToken);
    await GStorage.setting.delete(SettingBoxKey.castPeers);
  }

  /// 四位配对码，用于发送端回填确认
  static String newCode() {
    final value = Random.secure().nextInt(10000);
    return value.toString().padLeft(4, '0');
  }

  /// 发送端保存的令牌：key 为设备 ip
  static String? tokenFor(String ip) =>
      GStorage.setting.get('${SettingBoxKey.castPeerPrefix}$ip') as String?;

  static Future<void> saveToken(String ip, String token) async {
    await GStorage.setting.put('${SettingBoxKey.castPeerPrefix}$ip', token);
  }

  static Future<void> forget(String ip) async {
    await GStorage.setting.delete('${SettingBoxKey.castPeerPrefix}$ip');
  }

  /// 最近连接过的设备 IP，用于发现失败时兜底探测
  static List<String> get recentIps {
    final saved = GStorage.setting.get(SettingBoxKey.castRecentIps);
    if (saved is! String || saved.isEmpty) return const [];
    try {
      return (jsonDecode(saved) as List<dynamic>).whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> rememberIp(String ip) async {
    final list = [...recentIps];
    list.remove(ip);
    list.insert(0, ip);
    await GStorage.setting.put(
      SettingBoxKey.castRecentIps,
      jsonEncode(list.take(10).toList()),
    );
  }

  static String _randomToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

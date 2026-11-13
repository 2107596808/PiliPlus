import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/services/cast/cast_client.dart';
import 'package:PiliPlus/services/cast/cast_discovery.dart';
import 'package:PiliPlus/services/cast/cast_models.dart';
import 'package:PiliPlus/services/cast/cast_pairing.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// 设置页：本机互联信息（地址、二维码、配对管理、同播开关）
class CastLocalPage extends StatefulWidget {
  const CastLocalPage({super.key});

  @override
  State<CastLocalPage> createState() => _CastLocalPageState();
}

class _CastLocalPageState extends State<CastLocalPage> {
  String? _ip;
  String _name = '';
  bool _sync = false;

  /// 扫对方二维码进来时，对方地址
  String? _targetHost;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    if (args is Map && args['ip'] is String) {
      _targetHost = args['ip'] as String;
    }
    _load();
  }

  /// 扫码入口：探测对方设备并直接配对
  Future<void> _connectTarget() async {
    final host = _targetHost;
    if (host == null) return;
    SmartDialog.showLoading();
    final device = await CastDiscovery.probe(host);
    SmartDialog.dismiss();
    if (!mounted) return;
    if (device == null) {
      SmartDialog.showToast('对方设备暂时不可达，请确认在同一局域网且已开启接收');
      return;
    }
    final requested = await CastClient.requestPair(device, _name);
    if (!mounted) return;
    if (!requested) {
      SmartDialog.showToast('对方没有响应配对请求');
      return;
    }
    final controller = TextEditingController();
    final input = await SmartDialog.show<dynamic>(
      animationType: SmartAnimationType.centerFade_otherSlide,
      builder: (context) => AlertDialog(
        title: const Text('输入配对码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('请查看 ${device.name} 上显示的 4 位配对码'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(labelText: '配对码'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => SmartDialog.dismiss(result: controller.text),
            child: const Text('配对'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || input is! String) return;
    final token = await CastClient.submitPairCode(device, input, _name);
    if (!mounted) return;
    if (token == null) {
      SmartDialog.showToast('配对码不正确或已过期');
      return;
    }
    await CastPairing.rememberIp(device.ip);
    if (!mounted) return;
    SmartDialog.showToast('已与 ${device.name} 配对');
    setState(() => _targetHost = null);
  }

  Future<void> _load() async {
    final ip = await CastLocalAddress.primary();
    final name = await CastDeviceName.get();
    if (!mounted) return;
    setState(() {
      _ip = ip;
      _name = name;
      _sync = GStorage.setting.get(
        SettingBoxKey.enableCastSync,
        defaultValue: false,
      );
    });
  }

  String get _pairUri => 'piliplus://pair?ip=$_ip&port=${CastProtocol.port}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SimpleScaffold(
      appBar: AppBar(title: const Text('互联与推送')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          if (_targetHost != null) ...[
            Card(
              color: theme.colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: Text('扫码连接 $_targetHost'),
                subtitle: const Text('双方确认配对码后即可互推内容'),
                trailing: FilledButton(
                  onPressed: _connectTarget,
                  child: const Text('连接'),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('本机', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_name, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 4),
                  SelectableText(
                    _ip == null ? '未连接到局域网' : '$_ip:${CastProtocol.port}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  if (_ip != null) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        color: Colors.white,
                        child: PrettyQrView.data(
                          data: _pairUri,
                          decoration: const PrettyQrDecoration(
                            shape: PrettyQrSquaresSymbol(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        '同款 App 扫码即可直接连接本机',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('一起看'),
                  subtitle: const Text('与本机连接的设备同步暂停、播放与进度'),
                  trailing: Switch(
                    value: _sync,
                    onChanged: (value) async {
                      await GStorage.setting.put(
                        SettingBoxKey.enableCastSync,
                        value,
                      );
                      setState(() => _sync = value);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.link_off),
                  title: const Text('清除配对'),
                  subtitle: Text(
                    CastPairing.peers.isEmpty
                        ? '暂无已配对设备'
                        : '已配对：${CastPairing.peers.join('、')}',
                  ),
                  onTap: CastPairing.peers.isEmpty
                      ? null
                      : () async {
                          await CastPairing.clear();
                          SmartDialog.showToast('已清除配对，对方需重新连接');
                          setState(() {});
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

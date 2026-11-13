import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/loading_widget/loading_widget.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/services/cast/cast_client.dart';
import 'package:PiliPlus/services/cast/cast_discovery.dart';
import 'package:PiliPlus/services/cast/cast_models.dart';
import 'package:PiliPlus/services/cast/cast_pairing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// 发送端：设备列表页，点击即推送
class CastDeviceListPage extends StatefulWidget {
  const CastDeviceListPage({
    super.key,
    required this.payload,
    required this.from,
  });

  final CastPayload payload;
  final String from;

  @override
  State<CastDeviceListPage> createState() => _CastDeviceListPageState();
}

class _CastDeviceListPageState extends State<CastDeviceListPage> {
  List<CastDevice> _devices = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _onSearch();
  }

  Future<void> _onSearch() async {
    if (_isSearching) return;
    setState(() {
      _isSearching = true;
      _devices = [];
    });
    final devices = await CastDiscovery.discover();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _isSearching = false;
    });
  }

  Future<void> _push(CastDevice device) async {
    SmartDialog.showLoading();
    final ok = await CastClient.push(
      device,
      widget.payload,
      from: widget.from,
    );
    SmartDialog.dismiss();
    if (!mounted) return;
    if (ok) {
      await CastPairing.rememberIp(device.ip);
      SmartDialog.showToast('已推送到 ${device.name}');
      Get.back();
      return;
    }
    // 推送被拒，多半是对方处于配对模式：走一次配对
    await _pair(device);
  }

  Future<void> _pair(CastDevice device) async {
    final requested = await CastClient.requestPair(device, widget.from);
    if (!mounted) return;
    if (!requested) {
      SmartDialog.showToast('对方未响应，请确认对方已开启「接收设备推送」');
      return;
    }
    final controller = TextEditingController();
    final confirmed = await SmartDialog.show<dynamic>(
      animationType: SmartAnimationType.centerFade_otherSlide,
      builder: (context) => AlertDialog(
        title: const Text('确认配对码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('请查看 ${device.name} 上显示的 4 位配对码并输入'),
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
    if (!mounted || confirmed is! String) return;
    final token = await CastClient.submitPairCode(
      device,
      confirmed,
      widget.from,
    );
    if (!mounted) return;
    if (token == null) {
      SmartDialog.showToast('配对码不正确或已过期');
      return;
    }
    await CastPairing.rememberIp(device.ip);
    SmartDialog.showToast('配对成功');
    await _onSearch();
  }

  Future<void> _addManually() async {
    final controller = TextEditingController();
    final host = await SmartDialog.show<dynamic>(
      animationType: SmartAnimationType.centerFade_otherSlide,
      builder: (context) => AlertDialog(
        title: const Text('手动添加设备'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '设备 IP 或主机名',
            hintText: '192.168.1.10',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => SmartDialog.dismiss(result: controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || host is! String || host.trim().isEmpty) return;
    SmartDialog.showLoading();
    final device = await CastDiscovery.probe(host);
    SmartDialog.dismiss();
    if (!mounted) return;
    if (device == null) {
      SmartDialog.showToast('没有找到该设备，请检查 IP 与网络');
      return;
    }
    setState(() {
      _devices = [device, ..._devices.where((d) => d.ip != device.ip)];
    });
    SmartDialog.showToast('已添加 ${device.name}');
  }

  void _startSync(CastDevice device) {
    // 连接结果与状态都由同播页自己展示
    Get.toNamed(
      '/castSync',
      arguments: {'device': device, 'from': widget.from},
    );
  }

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('推送到设备'),
        actions: [
          IconButton(
            tooltip: '手动添加',
            onPressed: _addManually,
            icon: const Icon(Icons.add_link),
          ),
          IconButton(
            tooltip: '搜索',
            onPressed: _onSearch,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          if (_isSearching) linearLoading,
          ViewSliverSafeArea(sliver: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_isSearching && _devices.isEmpty) {
      return HttpError(
        errMsg: '没有发现设备\n请确认两台设备在同一局域网\n且对方开启了「接收设备推送」\n也可以右上角手动输入对方 IP',
        onReload: _onSearch,
      );
    }
    return SliverList.builder(
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        final paired = CastPairing.tokenFor(device.ip) != null;
        return ListTile(
          leading: Icon(paired ? Icons.link : Icons.phone_android),
          title: Text(device.name),
          subtitle: Text(
            paired ? '${device.ip} · 已配对' : device.ip,
          ),
          trailing: IconButton(
            tooltip: '一起看',
            onPressed: () => _startSync(device),
            icon: const Icon(Icons.sync),
          ),
          onTap: () => _push(device),
        );
      },
    );
  }
}

import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/loading_widget/loading_widget.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/services/cast/cast_client.dart';
import 'package:PiliPlus/services/cast/cast_discovery.dart';
import 'package:PiliPlus/services/cast/cast_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// 发送端：设备列表页，点击即推送
class CastDeviceListPage extends StatefulWidget {
  const CastDeviceListPage({
    super.key,
    required this.payload,
    required this.from,
  });

  final CastPushPayload payload;
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
    final ok = await CastClient.push(device, widget.payload, from: widget.from);
    SmartDialog.dismiss();
    if (!mounted) return;
    if (ok) {
      SmartDialog.showToast('已推送到 ${device.name}');
      Get.back();
    } else {
      SmartDialog.showToast('推送失败，请确认对方应用在前台');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('推送到设备'),
        actions: [
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
        errMsg: '没有发现设备\n请确认两台设备在同一局域网\n且对方开启了「接收设备推送」',
        onReload: _onSearch,
      );
    }
    return SliverList.builder(
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        return ListTile(
          leading: const Icon(Icons.phone_android),
          title: Text(device.name),
          subtitle: Text(device.address.address),
          onTap: () => _push(device),
        );
      },
    );
  }
}

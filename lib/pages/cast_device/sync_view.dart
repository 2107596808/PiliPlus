import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/services/cast/cast_models.dart';
import 'package:PiliPlus/services/cast/cast_sync_service.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:material_ui/material_ui.dart';

/// 一起看：显示连接状态与本机播放控制
class CastSyncPage extends StatefulWidget {
  const CastSyncPage({super.key, required this.device, required this.from});

  final CastDevice device;
  final String from;

  @override
  State<CastSyncPage> createState() => _CastSyncPageState();
}

class _CastSyncPageState extends State<CastSyncPage> {
  bool _connecting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    final ok = await CastSyncService.instance.connect(
      widget.device,
      from: widget.from,
    );
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _error = ok ? null : '无法建立连接，请确认对方已开启「一起看」';
    });
  }

  @override
  void dispose() {
    CastSyncService.instance.disconnect();
    super.dispose();
  }

  void _send(String action) {
    final player = PlPlayerController.instance;
    if (player == null) return;
    final position = player.positionInMilliseconds ~/ 1000;
    CastSyncService.instance.send(
      CastSyncPayload(action: action, positionSec: position),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final player = PlPlayerController.instance;
    final playing = player?.playerStatus.isPlaying ?? false;
    return SimpleScaffold(
      appBar: AppBar(title: Text('一起看 · ${widget.device.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_connecting)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!),
              ),
            )
          else ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: const Text('已连接'),
                    subtitle: Text(
                      '暂停、播放与进度会与 ${widget.device.name} 保持一致',
                    ),
                  ),
                  ListTile(
                    leading: Icon(playing ? Icons.pause : Icons.play_arrow),
                    title: Text(playing ? '暂停' : '播放'),
                    onTap: () => _send(playing ? 'pause' : 'play'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.sync),
                    title: const Text('同步当前进度'),
                    onTap: () => _send('seek'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

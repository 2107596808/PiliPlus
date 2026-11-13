import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/services/cast/cast_client.dart';
import 'package:PiliPlus/services/cast/cast_listener.dart';
import 'package:PiliPlus/services/cast/cast_models.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// 一起看：把本机播放状态同步给对端，并应用对端下发的控制
class CastSyncService {
  CastSyncService._();

  static final CastSyncService instance = CastSyncService._();

  CastSyncSession? _session;

  /// 应用远端指令期间不再回发，避免来回震荡
  bool _applyingRemote = false;

  Timer? _progressTimer;
  Timer? _debounce;

  /// 最近一次广播的播放/暂停状态，用于去重
  bool? _lastPlaying;
  int _lastPosition = 0;

  bool get connected => _session != null && !_session!.closed;

  String? get peerName => _session?.device.name;

  /// 发送端：与某台设备建立同播
  Future<bool> connect(CastDevice device, {required String from}) async {
    await disconnect();
    final session = await CastClient.connect(
      device,
      from: from,
      onSync: _onRemoteSync,
    );
    if (session == null) return false;
    _session = session;
    _startTicker();
    return true;
  }

  Future<void> disconnect() async {
    _progressTimer?.cancel();
    _debounce?.cancel();
    _progressTimer = null;
    _debounce = null;
    _lastPlaying = null;
    await _session?.close();
    _session = null;
  }

  /// 接收端：把远端指令应用到本机播放器
  void applyRemote(CastSyncPayload payload, String from) {
    // 未开启「一起看」时不接受远端控制，避免被动打断播放
    if (!Pref.enableCastSync) return;
    if (connected) return; // 已经在同播会话里，由会话回调处理
    _applyingRemote = true;
    try {
      _apply(payload);
    } finally {
      _applyingRemote = false;
    }
  }

  void _onRemoteSync(CastSyncPayload payload) {
    _applyingRemote = true;
    try {
      _apply(payload);
    } finally {
      _applyingRemote = false;
    }
  }

  void _apply(CastSyncPayload payload) {
    final player = PlPlayerController.instance;
    if (player == null) return;
    switch (payload.action) {
      case 'play':
        unawaited(player.play());
      case 'pause':
        unawaited(player.pause());
      case 'seek':
      case 'progress':
        final target = Duration(seconds: payload.positionSec);
        final current = Duration(
          milliseconds: player.positionInMilliseconds,
        );
        // 偏差超过 1.5 秒才纠正，避免频繁抖动
        if ((target - current).abs() > const Duration(milliseconds: 1500)) {
          unawaited(player.seekTo(target));
        }
    }
  }

  void _startTicker() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!connected) {
        _progressTimer?.cancel();
        return;
      }
      _emitProgress();
    });
  }

  void _emitProgress() {
    if (_applyingRemote || !connected) return;
    final player = PlPlayerController.instance;
    if (player == null) return;
    final playing = player.playerStatus.isPlaying;
    final position = player.positionInMilliseconds ~/ 1000;
    if (playing == _lastPlaying && (position - _lastPosition).abs() < 2) {
      return;
    }
    _lastPlaying = playing;
    _lastPosition = position;
    _session?.send(
      CastSyncPayload(
        action: playing ? 'play' : 'pause',
        positionSec: position,
      ),
    );
  }

  /// 播放器状态变化时由播放器侧调用，做去抖后广播
  void onLocalStateChanged() {
    if (!connected || _applyingRemote) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _emitProgress);
  }

  /// 主动下发一条同播指令（界面按钮使用）
  void send(CastSyncPayload payload) {
    if (!connected) return;
    _lastPlaying = null;
    _session?.send(payload);
  }

  /// 接收端把自己的状态回给所有连接
  void broadcastLocal() {
    if (_applyingRemote) return;
    final player = PlPlayerController.instance;
    if (player == null) return;
    try {
      CastListener.instance.broadcastSync(
        CastSyncPayload(
          action: player.playerStatus.isPlaying ? 'play' : 'pause',
          positionSec: player.positionInMilliseconds ~/ 1000,
        ),
      );
    } catch (e) {
      logger.w('CastSyncService: 广播失败 $e');
    }
  }
}

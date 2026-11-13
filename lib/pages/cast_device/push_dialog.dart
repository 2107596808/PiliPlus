import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/services/cast/cast_models.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';

/// 接收端收到推送后的确认弹窗
void showCastPushDialog(CastPayload payload, String from) {
  switch (payload) {
    case CastVideoPayload():
      _showVideoDialog(payload, from);
    case CastQueuePayload():
      _showQueueDialog(payload, from);
    case CastLinkPayload():
      _showLinkDialog(payload, from);
    case CastSyncPayload():
      break; // 同播由播放器直接应用，不打扰用户
  }
}

void _showVideoDialog(CastVideoPayload payload, String from) {
  SmartDialog.show(
    animationType: SmartAnimationType.centerFade_otherSlide,
    builder: (context) => AlertDialog(
      title: Text(from.isEmpty ? '收到视频推送' : '$from 推送了视频'),
      content: _videoContent(payload),
      actions: [
        const TextButton(
          onPressed: SmartDialog.dismiss,
          child: Text('忽略'),
        ),
        FilledButton(
          onPressed: () {
            SmartDialog.dismiss();
            _openPushedVideo(payload);
          },
          child: const Text('播放'),
        ),
      ],
    ),
  );
}

Widget _videoContent(CastVideoPayload payload) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (payload.cover.isNotEmpty) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            payload.cover,
            width: double.infinity,
            height: 120,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox(height: 120),
          ),
        ),
        const SizedBox(height: 12),
      ],
      Text(
        payload.title.isEmpty ? '未知视频' : payload.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      if (payload.positionSec > 0) ...[
        const SizedBox(height: 6),
        Text(
          '对方进度 ${_durationText(payload.positionSec)}',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    ],
  );
}

void _showQueueDialog(CastQueuePayload payload, String from) {
  SmartDialog.show(
    animationType: SmartAnimationType.centerFade_otherSlide,
    builder: (context) => AlertDialog(
      title: Text('$from 推送了 ${payload.length} 个视频'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: payload.length,
          itemBuilder: (context, index) {
            final item = payload.items[index];
            return ListTile(
              dense: true,
              title: Text(
                item.title.isEmpty ? item.bvid ?? '未知视频' : item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
      ),
      actions: [
        const TextButton(
          onPressed: SmartDialog.dismiss,
          child: Text('忽略'),
        ),
        FilledButton(
          onPressed: () {
            SmartDialog.dismiss();
            final first = payload.first;
            if (first != null) _openPushedVideo(first);
          },
          child: const Text('播放第一个'),
        ),
      ],
    ),
  );
}

void _showLinkDialog(CastLinkPayload payload, String from) {
  SmartDialog.show(
    animationType: SmartAnimationType.centerFade_otherSlide,
    builder: (context) => AlertDialog(
      title: Text(from.isEmpty ? '收到链接推送' : '$from 推送了链接'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (payload.title.isNotEmpty)
            Text(payload.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Text(
            payload.url,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        const TextButton(
          onPressed: SmartDialog.dismiss,
          child: Text('忽略'),
        ),
        FilledButton(
          onPressed: () {
            SmartDialog.dismiss();
            PiliScheme.routePushFromUrl(payload.url);
          },
          child: const Text('打开'),
        ),
      ],
    ),
  );
}

String _durationText(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) {
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

void _openPushedVideo(CastVideoPayload payload) {
  Get.toNamed(
    '/videoV',
    arguments: {
      'aid': payload.aid,
      'bvid': payload.bvid,
      'cid': payload.cid,
      'epId': payload.epId,
      'seasonId': payload.seasonId,
      'pgcType': payload.pgcType,
      'videoType': payload.type == 'pgc' ? VideoType.pgc : VideoType.ugc,
      'cover': payload.cover,
      'title': payload.title,
      'progress': payload.positionSec * 1000,
      'heroTag': 'cast_${const UuidV4().generate()}',
    },
    preventDuplicates: false,
  );
}

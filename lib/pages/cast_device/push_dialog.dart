import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/services/cast/cast_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';

/// 接收端收到推送后的确认弹窗
void showCastPushDialog(CastPushPayload payload, String from) {
  SmartDialog.show(
    animationType: SmartAnimationType.centerFade_otherSlide,
    builder: (context) => AlertDialog(
      title: Text(from.isEmpty ? '收到视频推送' : '$from 推送了视频'),
      content: Column(
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
            _openPushedVideo(payload);
          },
          child: const Text('播放'),
        ),
      ],
    ),
  );
}

void _openPushedVideo(CastPushPayload payload) {
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

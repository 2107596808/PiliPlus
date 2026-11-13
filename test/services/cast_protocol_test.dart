import 'package:PiliPlus/services/cast/cast_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CastMessage 编解码', () {
    test('push 视频消息往返后字段保持一致', () {
      final original = CastMessage.push(
        id: 'id-1',
        from: '手机',
        payload: const CastVideoPayload(
          type: 'ugc',
          bvid: 'BV1xx411c7mD',
          aid: 123,
          cid: 456,
          title: '标题',
          cover: 'https://example.com/c.jpg',
          positionSec: 42,
        ),
      );
      final parsed = CastMessage.tryParse(original.toJsonString());
      expect(parsed, isNotNull);
      expect(parsed!.type, 'push');
      expect(parsed.id, 'id-1');
      expect(parsed.app, CastProtocol.appId);
      expect(parsed.version, CastProtocol.version);
      final payload = parsed.payload;
      expect(payload, isA<CastVideoPayload>());
      payload as CastVideoPayload;
      expect(payload.bvid, 'BV1xx411c7mD');
      expect(payload.cid, 456);
      expect(payload.positionSec, 42);
    });

    test('队列消息按顺序还原每个视频', () {
      final message = CastMessage.push(
        id: 'q',
        from: '电脑',
        payload: const CastQueuePayload(
          title: '我的收藏夹',
          items: [
            CastVideoPayload(type: 'ugc', cid: 1, bvid: 'BV1'),
            CastVideoPayload(type: 'ugc', cid: 2, bvid: 'BV2'),
          ],
        ),
      );
      final parsed = CastMessage.tryParse(message.toJsonString());
      final payload = parsed!.payload;
      expect(payload, isA<CastQueuePayload>());
      payload as CastQueuePayload;
      expect(payload.length, 2);
      expect(payload.first?.bvid, 'BV1');
      expect(payload.items.last.cid, 2);
    });

    test('通用链接与同播消息各自还原为对应类型', () {
      final link = CastMessage.tryParse(
        CastMessage.push(
          id: 'l',
          from: 'x',
          payload: const CastLinkPayload(
            url: 'https://www.bilibili.com/video/BV1',
            title: 't',
          ),
        ).toJsonString(),
      )!.payload;
      expect(link, isA<CastLinkPayload>());
      expect((link! as CastLinkPayload).url, contains('BV1'));

      final sync = CastMessage.tryParse(
        CastMessage.sync(
          from: 'x',
          payload: const CastSyncPayload(action: 'seek', positionSec: 90),
        ).toJsonString(),
      )!.payload;
      expect(sync, isA<CastSyncPayload>());
      expect((sync! as CastSyncPayload).action, 'seek');
      expect((sync as CastSyncPayload).positionSec, 90);
    });

    test('未知 kind 与损坏文本都返回 null 而不是抛异常', () {
      expect(CastMessage.tryParse('not json'), isNull);
      expect(CastMessage.tryParse('[]'), isNull);
      final unknown = CastMessage.tryParse(
        '{"t":"push","v":2,"app":"${CastProtocol.appId}",'
        '"payload":{"kind":"unknown"}}',
      );
      expect(unknown?.payload, isNull);
    });

    test('配对消息携带配对码与令牌', () {
      final request = CastMessage.tryParse(
        CastMessage.pairRequest(id: 'p', from: '手机').toJsonString(),
      );
      expect(request?.type, 'pair_request');
      final submit = CastMessage.tryParse(
        CastMessage.pairSubmit(
          id: 'p',
          from: '手机',
          code: '0123',
        ).toJsonString(),
      );
      expect(submit?.code, '0123');
      final paired = CastMessage.tryParse(
        CastMessage.paired(id: 'p', token: 'tk', name: '电脑').toJsonString(),
      );
      expect(paired?.token, 'tk');
    });
  });
}

import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// 接收端：把配对码显示给用户，由发送端回填确认
void showCastPairCodeDialog(String from, String code) {
  SmartDialog.show(
    animationType: SmartAnimationType.centerFade_otherSlide,
    builder: (context) => AlertDialog(
      title: const Text('设备配对请求'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            from.isEmpty ? '有设备请求连接本机' : '$from 请求连接本机',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            code,
            style: const TextStyle(
              fontSize: 40,
              letterSpacing: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '对方输入这个配对码后即可连接',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: SmartDialog.dismiss,
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

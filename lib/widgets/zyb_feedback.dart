import 'package:flutter/material.dart';

/// 全局品牌反馈提示（屏幕中下部悬浮胶囊，单手下拉与操作视线极佳）
void showZybFeedback(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();

  final isDark = Theme.of(context).brightness == Brightness.dark;
  final durationMs = (error || message.length > 8) ? 800 : 500;

  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 140, left: 24, right: 24),
      padding: EdgeInsets.zero,
      duration: Duration(milliseconds: durationMs),
      content: Center(
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              // 浅色模式为温润奶油淡橙，夜间模式为深琥珀暗暖橙
              color: isDark ? const Color(0xF2281811) : const Color(0xFAFFF7F0),
              borderRadius: BorderRadius.circular(12), // 刚劲精致微圆角 12px
              border: Border.all(
                color: isDark
                    ? const Color(0xFFFF5F15).withValues(alpha: 0.48)
                    : const Color(0xFFFF5F15).withValues(alpha: 0.58), // 品牌暖橙细微光边
                width: 1.0,
              ),
              boxShadow: isDark
                  ? const [
                      BoxShadow(
                        color: Color(0x60000000),
                        blurRadius: 16,
                        offset: Offset(0, 5),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: const Color(0xFFFF5F15).withValues(alpha: 0.16),
                        blurRadius: 16,
                        offset: const Offset(0, 5),
                      ),
                      const BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  error
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_rounded,
                  color: error
                      ? (isDark ? const Color(0xFFFF5252) : const Color(0xFFE53935))
                      : const Color(0xFFFF5F15),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark
                          ? const Color(0xFFF7EBE3)
                          : const Color(0xFF2E1C12), // 深暖炭灰，在浅橙底上对比鲜明
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

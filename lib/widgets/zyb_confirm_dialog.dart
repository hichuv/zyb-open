import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 全局统一高反差双色实体确认弹窗
Future<bool?> showZybConfirmDialog({
  required BuildContext context,
  required String title,
  String? message,
  String cancelText = '取消',
  String confirmText = '确定',
  bool isDanger = false,
  Color? confirmColor,
}) {
  final colors = zybColors(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
                height: 1.3,
              ),
            ),
            if (message != null && message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(
                  fontSize: 13.5,
                  color: colors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Material(
                    color: isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFEFEFF2),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(ctx, false),
                      child: Container(
                        height: 42,
                        alignment: Alignment.center,
                        child: Text(
                          cancelText,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? const Color(0xFFE5E5EA)
                                : const Color(0xFF3A3A3C),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Material(
                    color: confirmColor ??
                        (isDanger ? const Color(0xFFF53F3F) : colors.primary),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(ctx, true),
                      child: Container(
                        height: 42,
                        alignment: Alignment.center,
                        child: Text(
                          confirmText,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

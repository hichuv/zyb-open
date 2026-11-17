import 'package:flutter/material.dart';

import '../services/deepseek_service.dart';
import '../services/haptic_service.dart';
import '../theme/app_theme.dart';
import 'zyb_ai_bubble_icon.dart';
import 'zyb_feedback.dart';

Future<bool> showDeepSeekConfigSheet(BuildContext context) async {
  final service = DeepSeekService();
  final current = await service.token() ?? '';
  if (!context.mounted) return false;
  final controller = TextEditingController(text: current);
  var obscure = true;
  var saving = false;
  String error = '';

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final colors = zybColors(context);
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const ZybAiBubbleIcon(size: 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'DeepSeek Token',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (current.isNotEmpty)
                        IconButton(
                          tooltip: '删除 Token',
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: colors.textMuted,
                          ),
                          onPressed: saving
                              ? null
                              : () async {
                                  await service.deleteToken();
                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext, false);
                                  }
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    autocorrect: false,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'sk-...',
                      filled: true,
                      fillColor: colors.surfaceSoft,
                      errorText: error.isEmpty ? null : error,
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setSheetState(() => obscure = !obscure),
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Token 仅加密保存在本机。AI 助手根据帖子内容生成精简回复与核心总结。',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.surfaceSoft,
                            foregroundColor: colors.textSecondary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(sheetContext, false),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: saving
                              ? null
                              : () async {
                                  final text = controller.text.trim();
                                  if (text.isEmpty) {
                                    setSheetState(
                                      () => error = '请输入 Token',
                                    );
                                    return;
                                  }
                                  setSheetState(() {
                                    saving = true;
                                    error = '';
                                  });
                                  try {
                                    await service.validateAndSave(text);
                                    if (sheetContext.mounted) {
                                      Navigator.pop(sheetContext, true);
                                    }
                                  } catch (e) {
                                    if (!sheetContext.mounted) return;
                                    setSheetState(() {
                                      saving = false;
                                      error = e.toString();
                                    });
                                  }
                                },
                          child: saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  controller.dispose();
  if (saved == true && context.mounted) {
    HapticService.instance.lightImpact();
    showZybFeedback(context, 'Token 已保存');
    return true;
  }
  return false;
}

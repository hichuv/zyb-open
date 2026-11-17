import 'package:flutter/material.dart';

import '../services/filter_service.dart';
import '../services/haptic_service.dart';
import '../theme/app_theme.dart';
import '../widgets/zyb_feedback.dart';

class FilterSettingsPage extends StatefulWidget {
  const FilterSettingsPage({super.key});

  @override
  State<FilterSettingsPage> createState() => _FilterSettingsPageState();
}

class _FilterSettingsPageState extends State<FilterSettingsPage> {
  final _filter = FilterService.instance;
  final _authorController = TextEditingController();
  final _keywordController = TextEditingController();
  final _authorFocus = FocusNode();
  final _keywordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _filter.load();
    _filter.addListener(_onFilterChanged);
  }

  @override
  void dispose() {
    _filter.removeListener(_onFilterChanged);
    _authorController.dispose();
    _keywordController.dispose();
    _authorFocus.dispose();
    _keywordFocus.dispose();
    super.dispose();
  }

  void _onFilterChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _addAuthor() async {
    final text = _authorController.text.trim();
    if (text.isEmpty) {
      showZybFeedback(context, '请输入要屏蔽的楼主昵称', error: true);
      return;
    }
    final success = await _filter.addAuthor(text);
    if (!mounted) return;
    if (success) {
      HapticService.instance.lightImpact();
      _authorController.clear();
      showZybFeedback(context, '已屏蔽楼主：$text');
    } else {
      showZybFeedback(context, '该楼主已在屏蔽列表中', error: true);
    }
  }

  Future<void> _removeAuthor(String author) async {
    HapticService.instance.lightImpact();
    await _filter.removeAuthor(author);
    if (mounted) {
      showZybFeedback(context, '已解除屏蔽：$author');
    }
  }

  Future<void> _addKeyword() async {
    final text = _keywordController.text.trim();
    if (text.isEmpty) {
      showZybFeedback(context, '请输入要屏蔽的关键词', error: true);
      return;
    }
    final success = await _filter.addKeyword(text);
    if (!mounted) return;
    if (success) {
      HapticService.instance.lightImpact();
      _keywordController.clear();
      showZybFeedback(context, '已屏蔽关键词：$text');
    } else {
      showZybFeedback(context, '该关键词已在屏蔽列表中', error: true);
    }
  }

  Future<void> _removeKeyword(String keyword) async {
    HapticService.instance.lightImpact();
    await _filter.removeKeyword(keyword);
    if (mounted) {
      showZybFeedback(context, '已删除屏蔽词：$keyword');
    }
  }

  void _openManageSheet({
    required BuildContext context,
    required String title,
    required List<String> Function() getItems,
    required IconData itemIcon,
    required Function(String) onRemove,
  }) {
    final colors = zybColors(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final items = getItems();
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.72,
              ),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 顶部拉手条
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // 弹窗标题
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
                    child: Row(
                      children: [
                        Text(
                          '$title (${items.length})',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: colors.textMuted),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: colors.divider),
                  // 名单列表
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined, size: 40, color: colors.textMuted),
                          const SizedBox(height: 10),
                          Text(
                            '暂无屏蔽记录',
                            style: TextStyle(fontSize: 13, color: colors.textMuted),
                          ),
                        ],
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: colors.divider.withValues(alpha: 0.5)),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                            leading: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: colors.primarySoft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Icon(itemIcon, size: 16, color: colors.primary),
                            ),
                            title: Text(
                              item,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            trailing: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              ),
                              onPressed: () async {
                                await onRemove(item);
                                setModalState(() {});
                                if (mounted) setState(() {});
                              },
                              icon: const Icon(Icons.delete_outline_rounded, size: 16),
                              label: const Text('移除', style: TextStyle(fontSize: 12.5)),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('屏蔽设置'),
        centerTitle: true,
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
      ),
      body: RefreshIndicator(
        color: colors.primary,
        onRefresh: () async {
          HapticService.instance.lightImpact();
          await _filter.load(force: true);
          if (mounted) {
            setState(() {});
            showZybFeedback(context, '刷新成功');
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            // 顶部温馨提示（精简为2行）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colors.primarySoft.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.2),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '规则保存在本机生效。\n命中规则的帖子将在首页和搜索中自动隐藏。',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 模块 1：屏蔽楼主（按昵称）
            _buildCompactCard(
              colors: colors,
              title: '屏蔽楼主（按昵称）',
              icon: Icons.person_off_outlined,
              controller: _authorController,
              focusNode: _authorFocus,
              hintText: '输入楼主昵称（如：赚友小明）',
              onAdd: _addAuthor,
              count: _filter.blockedAuthors.length,
              manageTitle: '查看与管理已屏蔽名单',
              onManage: () => _openManageSheet(
                context: context,
                title: '已屏蔽楼主名单',
                getItems: () => _filter.blockedAuthors,
                itemIcon: Icons.person_rounded,
                onRemove: _removeAuthor,
              ),
            ),

            const SizedBox(height: 14),

            // 模块 2：屏蔽关键词
            _buildCompactCard(
              colors: colors,
              title: '屏蔽关键词',
              icon: Icons.filter_alt_off_outlined,
              controller: _keywordController,
              focusNode: _keywordFocus,
              hintText: '输入屏蔽关键词（如：助力）',
              onAdd: _addKeyword,
              count: _filter.blockedKeywords.length,
              manageTitle: '查看与管理屏蔽词库',
              onManage: () => _openManageSheet(
                context: context,
                title: '已添加屏蔽词库',
                getItems: () => _filter.blockedKeywords,
                itemIcon: Icons.tag_rounded,
                onRemove: _removeKeyword,
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactCard({
    required ZybColors colors,
    required String title,
    required IconData icon,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required VoidCallback onAdd,
    required int count,
    required String manageTitle,
    required VoidCallback onManage,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.cardBorder, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: colors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.cardBorder, width: 0.6),
                ),
                child: Text(
                  '$count 个',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 输入与添加框
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: TextStyle(fontSize: 13.5, color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: colors.textMuted,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
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
                  onSubmitted: (_) => onAdd(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  minimumSize: const Size(64, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onAdd,
                child: const Text('添加', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 查看与管理统一入口（主页面绝不外显零碎标签，保持高度恒定）
          InkWell(
            onTap: onManage,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surfaceSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.cardBorder, width: 0.6),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.format_list_bulleted_rounded,
                    size: 16,
                    color: count > 0 ? colors.primary : colors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      count > 0 ? '$manageTitle ($count)' : '暂无屏蔽记录',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: count > 0 ? colors.textPrimary : colors.textMuted,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

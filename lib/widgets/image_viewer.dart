import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/constants.dart';
import '../services/haptic_service.dart';
import '../theme/app_theme.dart';
import 'zyb_feedback.dart';

const _platform = MethodChannel('zybapp/platform');

/// 打开大图查看器（微信/小红书同款：沉浸全屏、大拇指随手下滑退出、PageView平滑横向阻尼翻页、双击放大）
void openImageViewer(
  BuildContext context,
  List<String> images, {
  int initialIndex = 0,
  bool local = false,
}) {
  final cleanImages = images.where((url) => url.isNotEmpty).toList();
  if (cleanImages.isEmpty) return;
  final safeInitial = initialIndex.clamp(0, cleanImages.length - 1);
  final targetUrl = cleanImages[safeInitial];

  final uniqueImages = <String>[];
  final seen = <String>{};
  int resolvedIndex = 0;
  for (final img in cleanImages) {
    if (seen.add(img)) {
      if (img == targetUrl && resolvedIndex == 0) {
        resolvedIndex = uniqueImages.length;
      }
      uniqueImages.add(img);
    }
  }

  Navigator.push(
    context,
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, animation, _) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: _ImageViewer(
          images: uniqueImages,
          initialIndex: resolvedIndex,
          local: local,
        ),
      ),
    ),
  );
}

class _ImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final bool local;

  const _ImageViewer({
    required this.images,
    required this.initialIndex,
    required this.local,
  });

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer>
    with SingleTickerProviderStateMixin {
  late int _index = widget.initialIndex;
  late final PageController _pageController;

  // 下拉拖拽关闭手势相关状态
  double _dragOffsetY = 0.0;
  double _dragOffsetX = 0.0;
  bool _isDraggingDown = false;
  bool _controlsVisible = true;
  bool _isCurrentZoomed = false;

  late final AnimationController _resetAnimController;
  Animation<Offset>? _resetOffsetAnim;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _resetAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        if (!mounted || _resetOffsetAnim == null) return;
        setState(() {
          _dragOffsetX = _resetOffsetAnim!.value.dx;
          _dragOffsetY = _resetOffsetAnim!.value.dy;
        });
      })..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _isDraggingDown = false;
            _dragOffsetY = 0.0;
            _dragOffsetX = 0.0;
          });
        }
      });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _resetAnimController.dispose();
    super.dispose();
  }

  void _onScaleChanged(int pageIndex, bool isZoomed) {
    if (pageIndex == _index && _isCurrentZoomed != isZoomed) {
      setState(() => _isCurrentZoomed = isZoomed);
    }
  }

  void _startResetAnimation() {
    _resetAnimController.stop();
    final startOffset = Offset(_dragOffsetX, _dragOffsetY);
    _resetOffsetAnim = Tween<Offset>(
      begin: startOffset,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _resetAnimController, curve: Curves.easeOutCubic),
    );
    _resetAnimController.reset();
    _resetAnimController.forward();
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (_isCurrentZoomed) return;
    _isDraggingDown = true;
    _resetAnimController.stop();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_isCurrentZoomed) return;
    setState(() {
      _dragOffsetY += details.delta.dy;
      _dragOffsetX += details.delta.dx * 0.3; // 微弱横向跟手
      if (_controlsVisible) _controlsVisible = false;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_isCurrentZoomed) return;
    final velocity = details.primaryVelocity ?? 0;
    // 如果向下拖动超过 90px 或者释放速度明显向下，优雅关闭
    if (_dragOffsetY > 90 || velocity > 400) {
      Navigator.pop(context);
      return;
    }

    _startResetAnimation();
  }

  void _onVerticalDragCancel() {
    if (!_isDraggingDown) return;
    _startResetAnimation();
  }

  Future<void> _saveCurrentImage() async {
    final url = widget.images[_index];
    if (widget.local) return;
    try {
      await _platform.invokeMethod<void>('saveImage', {'url': url});
      if (mounted) {
        HapticService.instance.lightImpact();
        showZybFeedback(context, '保存成功');
      }
    } catch (_) {
      if (mounted) {
        showZybFeedback(context, '图片保存失败', error: true);
      }
    }
  }

  Future<void> _showImageActions() async {
    HapticService.instance.lightImpact();
    final colors = zybColors(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!widget.local)
                ListTile(
                  leading: const Icon(Icons.download_rounded, color: Color(0xFFFF5F15)),
                  title: const Text('保存图片到相册', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _saveCurrentImage();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('关闭'),
                onTap: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 根据下拉距离计算背景黑色透明度（1.0 -> 0.0）
    final dragDist = _dragOffsetY.clamp(0.0, 300.0);
    final bgOpacity = (1.0 - (dragDist / 260.0)).clamp(0.0, 1.0);
    // 根据下拉距离等比例缩小图片（1.0 -> 0.65）
    final scale = (1.0 - (dragDist / 700.0)).clamp(0.65, 1.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. 沉浸式黑色背景（随下拉平滑渐隐）
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: bgOpacity),
              ),
            ),

            // 2. 核心大图展示层（支持微信同款下滑跟随 + PageView 翻页）
            Positioned.fill(
              child: GestureDetector(
                onVerticalDragStart: _onVerticalDragStart,
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
                onVerticalDragCancel: _onVerticalDragCancel,
                child: Transform.translate(
                offset: Offset(_dragOffsetX, _dragOffsetY),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.center,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: widget.images.length,
                    physics: _isCurrentZoomed
                        ? const NeverScrollableScrollPhysics()
                        : const BouncingScrollPhysics(),
                    onPageChanged: (i) {
                      setState(() {
                        _index = i;
                        _isCurrentZoomed = false;
                      });
                    },
                    itemBuilder: (context, pageIndex) {
                      return SizedBox(
                        key: ValueKey('viewer-frame-$pageIndex'),
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width,
                            height: MediaQuery.of(context).size.height,
                            child: _ZoomableImagePage(
                              key: ValueKey(widget.images[pageIndex]),
                              source: widget.images[pageIndex],
                              local: widget.local,
                              pageIndex: pageIndex,
                              currentPage: _index,
                              onTap: () => setState(() => _controlsVisible = !_controlsVisible),
                              onLongPress: _showImageActions,
                              onScaleChanged: _onScaleChanged,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // 3. 顶部沉浸半透明操作栏（返回按钮 + 1/N 计数胶囊）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_controlsVisible || _isDraggingDown,
              child: AnimatedOpacity(
                opacity: (_controlsVisible && !_isDraggingDown) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: SafeArea(
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 左侧返回按钮
                        Tooltip(
                          message: '关闭',
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.4),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                        // 中间计数胶囊
                        if (widget.images.length > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '${_index + 1} / ${widget.images.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          )
                        else
                          const SizedBox(width: 38),
                        // 右侧占位
                        const SizedBox(width: 38),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 4. 底部“保存图片”快捷按钮
          if (!widget.local)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_controlsVisible || _isDraggingDown,
                child: AnimatedOpacity(
                  opacity: (_controlsVisible && !_isDraggingDown) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24, right: 24),
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: GestureDetector(
                          onTap: _saveCurrentImage,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.download_rounded, color: Colors.white, size: 18),
                                SizedBox(width: 6),
                                Text(
                                  '保存',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
}

/// 支持双指缩放与双击放大的单张图片展示组件
class _ZoomableImagePage extends StatefulWidget {
  final String source;
  final bool local;
  final int pageIndex;
  final int currentPage;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final void Function(int pageIndex, bool isZoomed) onScaleChanged;

  const _ZoomableImagePage({
    super.key,
    required this.source,
    required this.local,
    required this.pageIndex,
    required this.currentPage,
    required this.onTap,
    required this.onLongPress,
    required this.onScaleChanged,
  });

  @override
  State<_ZoomableImagePage> createState() => _ZoomableImagePageState();
}

class _ZoomableImagePageState extends State<_ZoomableImagePage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformation = TransformationController();
  TapDownDetails? _doubleTapDetails;
  late final AnimationController _zoomAnimController;
  Animation<Matrix4>? _zoomAnim;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (!mounted || _zoomAnim == null) return;
        _transformation.value = _zoomAnim!.value;
      });
  }

  @override
  void didUpdateWidget(covariant _ZoomableImagePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPage != widget.pageIndex && _isZoomed) {
      _zoomAnimController.stop();
      _transformation.value = Matrix4.identity();
      _isZoomed = false;
      widget.onScaleChanged(widget.pageIndex, false);
    }
  }

  @override
  void dispose() {
    _transformation.dispose();
    _zoomAnimController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final currentScale = _transformation.value.getMaxScaleOnAxis();
    final targetScale = currentScale > 1.2 ? 1.0 : 2.5;

    _zoomAnimController.stop();

    final Matrix4 endMatrix;
    if (targetScale == 1.0) {
      endMatrix = Matrix4.identity();
    } else {
      final tapPos = _doubleTapDetails?.localPosition ?? Offset.zero;
      final scenePoint = _transformation.toScene(tapPos);
      final size = MediaQuery.of(context).size;
      final dx = (-scenePoint.dx * targetScale + size.width / 2)
          .clamp(-size.width * (targetScale - 1), 0.0);
      final dy = (-scenePoint.dy * targetScale + size.height / 2)
          .clamp(-size.height * (targetScale - 1), 0.0);
      endMatrix = Matrix4.identity()
        ..storage[0] = targetScale
        ..storage[5] = targetScale
        ..storage[12] = dx
        ..storage[13] = dy;
    }

    _zoomAnim = Matrix4Tween(
      begin: _transformation.value,
      end: endMatrix,
    ).animate(CurvedAnimation(parent: _zoomAnimController, curve: Curves.easeOutCubic));

    final isTargetZoomed = targetScale > 1.05;
    setState(() => _isZoomed = isTargetZoomed);
    widget.onScaleChanged(widget.pageIndex, isTargetZoomed);

    _zoomAnimController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: _handleDoubleTap,
      onLongPress: widget.onLongPress,
      child: SizedBox.expand(
        child: InteractiveViewer(
          transformationController: _transformation,
          minScale: 1.0,
          maxScale: 4.5,
          panEnabled: _isZoomed,
          scaleEnabled: true,
          clipBehavior: Clip.none,
          onInteractionUpdate: (details) {
            final scale = _transformation.value.getMaxScaleOnAxis();
            final zoomed = scale > 1.05;
            if (zoomed != _isZoomed) {
              setState(() => _isZoomed = zoomed);
              widget.onScaleChanged(widget.pageIndex, zoomed);
            }
          },
          onInteractionEnd: (details) {
            final scale = _transformation.value.getMaxScaleOnAxis();
            if (scale <= 1.02) {
              _transformation.value = Matrix4.identity();
              if (_isZoomed) {
                setState(() => _isZoomed = false);
                widget.onScaleChanged(widget.pageIndex, false);
              }
            }
          },
          child: Center(
            child: widget.local
                ? Image.file(File(widget.source), fit: BoxFit.contain)
                : CachedNetworkImage(
                    imageUrl: widget.source,
                    httpHeaders: const {
                      'Referer': baseUrl,
                      'User-Agent': mobileUserAgent,
                    },
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Color(0xFFFF5F15),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.broken_image_rounded,
                            color: Colors.white54,
                            size: 48,
                          ),
                          SizedBox(height: 10),
                          Text(
                            '图片加载失败',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// 严格参照用户提供的视觉参考图定制的 AI 智能助手双气泡图标
class ZybAiBubbleIcon extends StatelessWidget {
  final double size;

  const ZybAiBubbleIcon({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF539DF8),
            Color(0xFF2B7AF3),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2B7AF3).withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // 后置半透明气泡
          Positioned(
            right: size * 0.15,
            top: size * 0.22,
            child: Container(
              width: size * 0.44,
              height: size * 0.38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(size * 0.12),
              ),
            ),
          ),
          // 前置白色主气泡
          Positioned(
            left: size * 0.15,
            bottom: size * 0.20,
            child: Container(
              width: size * 0.52,
              height: size * 0.44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(size * 0.14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text(
                'AI',
                style: TextStyle(
                  color: Color(0xFF2B7AF3),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

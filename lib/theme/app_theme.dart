import 'package:flutter/material.dart';

abstract final class ZybDesign {
  static const double radiusSmall = 10;
  static const double radius = 14;
  static const double radiusLarge = 22;
  static const double pagePadding = 14;
  static const Duration motion = Duration(milliseconds: 260);
  static const Curve motionCurve = Curves.easeOutCubic;
}

@immutable
class ZybColors extends ThemeExtension<ZybColors> {
  final Color background;
  final Color headerStart;
  final Color headerEnd;
  final Color surface;
  final Color surfaceSoft;
  final Color surfaceWarm;
  final Color cardBorder;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color primary;
  final Color primarySoft;
  final Color shadow;
  final Color navBackground;
  final Color overlay;

  const ZybColors({
    required this.background,
    required this.headerStart,
    required this.headerEnd,
    required this.surface,
    required this.surfaceSoft,
    required this.surfaceWarm,
    required this.cardBorder,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.primary,
    required this.primarySoft,
    required this.shadow,
    required this.navBackground,
    required this.overlay,
  });

  static const light = ZybColors(
    background: Color(0xFFF7F8FA),
    headerStart: Color(0xFFFFFFFF),
    headerEnd: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceSoft: Color(0xFFF2F3F5),
    surfaceWarm: Color(0xFFFFFBF9),
    cardBorder: Color(0xFFE5E6EB),
    divider: Color(0xFFE5E6EB),
    textPrimary: Color(0xFF1D2129),
    textSecondary: Color(0xFF4E5969),
    textMuted: Color(0xFF86909C),
    primary: Color(0xFFFF5F15),
    primarySoft: Color(0xFFFFF0EA),
    shadow: Color(0x0A000000),
    navBackground: Color(0xFFFFFFFF),
    overlay: Color(0x73000000),
  );

  static const dark = ZybColors(
    background: Color(0xFF121212),
    headerStart: Color(0xFF18181A),
    headerEnd: Color(0xFF18181A),
    surface: Color(0xFF1E1E20),
    surfaceSoft: Color(0xFF262629),
    surfaceWarm: Color(0xFF22201E),
    cardBorder: Color(0xFF2B2B2E),
    divider: Color(0xFF2B2B2E),
    textPrimary: Color(0xFFF2F3F5),
    textSecondary: Color(0xFFC9CDD4),
    textMuted: Color(0xFF86909C),
    primary: Color(0xFFFF7A38),
    primarySoft: Color(0x26FF7A38),
    shadow: Color(0x52000000),
    navBackground: Color(0xF219191B),
    overlay: Color(0x99000000),
  );

  @override
  ZybColors copyWith({
    Color? background,
    Color? headerStart,
    Color? headerEnd,
    Color? surface,
    Color? surfaceSoft,
    Color? surfaceWarm,
    Color? cardBorder,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? primary,
    Color? primarySoft,
    Color? shadow,
    Color? navBackground,
    Color? overlay,
  }) {
    return ZybColors(
      background: background ?? this.background,
      headerStart: headerStart ?? this.headerStart,
      headerEnd: headerEnd ?? this.headerEnd,
      surface: surface ?? this.surface,
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      surfaceWarm: surfaceWarm ?? this.surfaceWarm,
      cardBorder: cardBorder ?? this.cardBorder,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      primary: primary ?? this.primary,
      primarySoft: primarySoft ?? this.primarySoft,
      shadow: shadow ?? this.shadow,
      navBackground: navBackground ?? this.navBackground,
      overlay: overlay ?? this.overlay,
    );
  }

  @override
  ZybColors lerp(ThemeExtension<ZybColors>? other, double t) {
    if (other is! ZybColors) return this;
    return ZybColors(
      background: Color.lerp(background, other.background, t)!,
      headerStart: Color.lerp(headerStart, other.headerStart, t)!,
      headerEnd: Color.lerp(headerEnd, other.headerEnd, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSoft: Color.lerp(surfaceSoft, other.surfaceSoft, t)!,
      surfaceWarm: Color.lerp(surfaceWarm, other.surfaceWarm, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      navBackground: Color.lerp(navBackground, other.navBackground, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
    );
  }
}

ZybColors zybColors(BuildContext context) =>
    Theme.of(context).extension<ZybColors>() ?? ZybColors.light;

ThemeData zybTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = dark ? ZybColors.dark : ZybColors.light;
  return ThemeData(
    useMaterial3: false,
    brightness: brightness,
    primaryColor: colors.primary,
    scaffoldBackgroundColor: colors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: colors.primary,
      brightness: brightness,
      primary: colors.primary,
      surface: colors.surface,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: colors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      iconTheme: IconThemeData(color: colors.textPrimary, size: 22),
    ),
    dividerTheme: DividerThemeData(color: colors.divider, thickness: .7),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZybDesign.radiusLarge),
        side: BorderSide(color: colors.cardBorder, width: .8),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surface,
      modalBackgroundColor: colors.surface,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: colors.divider,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ZybDesign.radiusLarge),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZybDesign.radius),
        side: BorderSide(color: colors.cardBorder, width: .7),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceSoft,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      hintStyle: TextStyle(color: colors.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZybDesign.radius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZybDesign.radius),
        borderSide: BorderSide(color: colors.cardBorder, width: .7),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZybDesign.radius),
        borderSide: BorderSide(color: colors.primary, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(44, 44),
        elevation: 0,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZybDesign.radius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.textSecondary,
        minimumSize: const Size(44, 44),
        side: BorderSide(color: colors.cardBorder),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZybDesign.radius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.primary,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZybDesign.radiusSmall),
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.primary),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.surface,
      contentTextStyle: TextStyle(color: colors.textPrimary),
      elevation: 8,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZybDesign.radius),
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[colors],
  );
}

Route<T> zybHorizontalPageRoute<T>({
  required WidgetBuilder builder,
  bool fromLeft = false,
}) {
  final begin = fromLeft ? const Offset(-1, 0) : const Offset(1, 0);
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(begin: begin, end: Offset.zero).animate(curved),
        child: child,
      );
    },
  );
}

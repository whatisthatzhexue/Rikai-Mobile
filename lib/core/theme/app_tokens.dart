import 'package:flutter/material.dart';

/// Normative design tokens for Rikai-Mobile.
///
/// See `docs/design-tokens.md`. All UI (existing and new) must use these
/// tokens through [ThemeData]/`AppTheme` instead of hard-coded values.
abstract final class AppColors {
  // Blue / white brand palette (TDesign-compatible brand blue).
  static const Color blue50 = Color(0xFFE8F1FF);
  static const Color blue100 = Color(0xFFD4E4FF);
  static const Color blue500 = Color(0xFF0052D9);
  static const Color blue600 = Color(0xFF0046B8);
  static const Color blue700 = Color(0xFF003A99);

  static const Color primary = blue500;
  static const Color primaryPressed = blue600;
  static const Color primaryContainer = blue50;
  static const Color onPrimaryContainer = blue700;

  static const Color surface = Colors.white;
  static const Color background = Color(0xFFF5F7FA);
  static const Color surfaceMuted = Color(0xFFF0F4F9);

  static const Color textPrimary = Color(0xFF181818);
  static const Color textSecondary = Color(0xFF5C6470);
  static const Color textTertiary = Color(0xFF8A929E);

  static const Color border = Color(0xFFDCE3EC);
  static const Color divider = Color(0xFFEDF1F6);

  static const Color error = Color(0xFFD54941);
  static const Color warning = Color(0xFFE37318);
  static const Color success = Color(0xFF2BA471);

  static const Color transparent = Colors.transparent;
}

abstract final class AppTypography {
  static const String fontFamily = 'HarmonyOS Sans SC';
  static const List<String> fontFamilyFallback = [
    'Noto Sans CJK SC',
    'Noto Sans SC',
    'sans-serif',
  ];

  /// Design-draft sizes are expressed at 3x. Flutter logical sizes are the
  /// values used in `TextStyle.fontSize`.
  static const double displayDesignPx = 72;
  static const double headlineDesignPx = 48;
  static const double titleDesignPx = 36;

  static const double display = 24; // 72 / 3
  static const double headline = 16; // 48 / 3
  static const double title = 12; // 36 / 3

  static const double displayHeight = 1.25;
  static const double textHeight = 1.5;

  /// Reader content is a user setting (not UI chrome), documented in the
  /// design tokens as the reading scale.
  static const double readerMin = 14;
  static const double readerMax = 30;
  static const double readerDefault = 20;
  static const double furiganaRatio = 0.55;
}

abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class AppRadius {
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double pill = 999;
}

abstract final class AppSizes {
  static const double appBar = 52;
  static const double control = 40;
  static const double field = 44;
  static const double chip = 28;
  static const double iconSmall = 16;
  static const double icon = 20;
  static const double iconLarge = 24;
  static const double emptyIcon = 40;
  static const double heroIcon = 48;
  static const double pageMaxWidth = 720;
  static const double borderWidth = 1;
}

abstract final class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: AppColors.primary,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.primaryContainer,
      onSecondaryContainer: AppColors.onPrimaryContainer,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerHighest: AppColors.surfaceMuted,
      error: AppColors.error,
      onError: Colors.white,
      outline: AppColors.border,
      outlineVariant: AppColors.divider,
      shadow: Color(0x0F000000),
      scrim: Color(0x66000000),
    );

    final textTheme = const TextTheme(
      displayLarge: TextStyle(
        fontSize: AppTypography.display,
        height: AppTypography.displayHeight,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      displayMedium: TextStyle(
        fontSize: AppTypography.display,
        height: AppTypography.displayHeight,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      displaySmall: TextStyle(
        fontSize: AppTypography.display,
        height: AppTypography.displayHeight,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: AppTypography.display,
        height: AppTypography.displayHeight,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: AppTypography.display,
        height: AppTypography.displayHeight,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: AppTypography.headline,
        height: AppTypography.textHeight,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: AppTypography.title,
        height: AppTypography.textHeight,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
      bodyLarge: TextStyle(
        fontSize: AppTypography.headline,
        height: AppTypography.textHeight,
        color: AppColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: AppTypography.headline,
        height: AppTypography.textHeight,
        color: AppColors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: AppTypography.title,
        height: AppTypography.textHeight,
        color: AppColors.textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: AppTypography.headline,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: AppColors.onPrimaryContainer,
      ),
      labelMedium: TextStyle(
        fontSize: AppTypography.title,
        height: 1.25,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: AppTypography.title,
        height: 1.25,
        color: AppColors.textTertiary,
      ),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppTypography.fontFamily,
      fontFamilyFallback: AppTypography.fontFamilyFallback,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.surface,
      visualDensity: VisualDensity.compact,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,
    );

    final roundedShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: AppColors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: AppSizes.appBar,
        iconTheme: IconThemeData(
          size: AppSizes.icon,
          color: AppColors.textSecondary,
        ),
        titleTextStyle: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: AppTypography.headline,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        shape: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: AppColors.transparent,
        shadowColor: AppColors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.primary.withValues(alpha: 0.35);
            }
            if (states.contains(WidgetState.pressed)) {
              return AppColors.primaryPressed;
            }
            return AppColors.primary;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(64, AppSizes.control)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: AppTypography.headline,
              fontWeight: FontWeight.w600,
            ),
          ),
          shape: WidgetStatePropertyAll(roundedShape),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(AppColors.primary),
          minimumSize: const WidgetStatePropertyAll(Size(64, AppSizes.control)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.border),
          ),
          shape: WidgetStatePropertyAll(roundedShape),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: AppTypography.headline,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(AppColors.primary),
          minimumSize: const WidgetStatePropertyAll(Size(40, AppSizes.control)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
          shape: WidgetStatePropertyAll(roundedShape),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: AppTypography.headline,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(AppSizes.control, AppSizes.control),
          ),
          iconSize: const WidgetStatePropertyAll(AppSizes.icon),
          foregroundColor: const WidgetStatePropertyAll(
            AppColors.textSecondary,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: const TextStyle(
          fontSize: AppTypography.headline,
          color: AppColors.textTertiary,
        ),
        labelStyle: const TextStyle(
          fontSize: AppTypography.title,
          color: AppColors.textSecondary,
        ),
        helperStyle: const TextStyle(
          fontSize: AppTypography.title,
          color: AppColors.textTertiary,
        ),
        errorStyle: const TextStyle(
          fontSize: AppTypography.title,
          color: AppColors.error,
        ),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceMuted,
        selectedColor: AppColors.primaryContainer,
        disabledColor: AppColors.surfaceMuted,
        side: const BorderSide(color: AppColors.transparent),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        labelStyle: const TextStyle(
          fontSize: AppTypography.title,
          color: AppColors.textPrimary,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: AppTypography.title,
          color: AppColors.onPrimaryContainer,
        ),
        showCheckmark: false,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: AppSizes.borderWidth,
        space: AppSizes.borderWidth,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        minVerticalPadding: AppSpacing.sm,
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        titleTextStyle: TextStyle(
          fontSize: AppTypography.headline,
          height: 1.4,
          color: AppColors.textPrimary,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: AppTypography.title,
          height: 1.5,
          color: AppColors.textSecondary,
        ),
        visualDensity: VisualDensity.compact,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.transparent,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: AppColors.border,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: AppTypography.headline,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: AppTypography.headline,
          height: AppTypography.textHeight,
          color: AppColors.textPrimary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: AppTypography.headline,
          color: Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        dividerColor: AppColors.border,
        labelStyle: TextStyle(
          fontSize: AppTypography.headline,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(fontSize: AppTypography.headline),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.primaryContainer,
        circularTrackColor: AppColors.primaryContainer,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.border;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(AppColors.transparent),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.primaryContainer,
        thumbColor: AppColors.primary,
        overlayColor: Color(0x240052D9),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: AppColors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.border),
        ),
        textStyle: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: AppTypography.headline,
          color: AppColors.textPrimary,
        ),
      ),
      iconTheme: const IconThemeData(
        size: AppSizes.icon,
        color: AppColors.textSecondary,
      ),
    );
  }
}

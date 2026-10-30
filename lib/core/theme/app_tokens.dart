import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_fonts.dart';

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

  /// Deep blue used by the home brand header and drawer header.
  static const Color header = blue700;
  static const Color onHeader = Colors.white;

  static const Color textPrimary = Color(0xFF181818);
  static const Color textSecondary = Color(0xFF5C6470);
  static const Color textTertiary = Color(0xFF8A929E);

  static const Color border = Color(0xFFDCE3EC);
  static const Color divider = Color(0xFFEDF1F6);

  static const Color error = Color(0xFFD54941);
  static const Color warning = Color(0xFFE37318);
  static const Color success = Color(0xFF2BA471);

  /// Camera preview controls sit on this scrim so they stay readable over
  /// arbitrary photo content.
  static const Color cameraScrim = Color(0x99000000);
  static const Color cameraControl = Colors.white;
  static const Color cameraBackground = Colors.black;

  static const Color transparent = Colors.transparent;
}

abstract final class AppTypography {
  static const String fontFamily = AppFonts.harmony;
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

  /// Secondary/helper copy in forms and settings. Always allowed to wrap.
  static const double helper = 14;

  /// Help/copyright section headings and other long-form sections.
  static const double sectionHeading = 18;

  /// Dictionary search result headword (1.5× the 16sp list title).
  static const double entryTitle = 24;

  /// Reader content is a user setting (not UI chrome), documented in the
  /// design tokens as the reading scale.
  static const double readerMin = 14;
  static const double readerMax = 30;
  static const double readerDefault = 20;
  static const double furiganaRatio = 0.55;

  /// OCR preview inside the multi-select photo grid. Large enough to read
  /// without opening each photo.
  static const double ocrPreview = 20;

  /// Home action buttons: 72dp tall, centered content. The label was reduced
  /// by 20% from the first revision (40sp → 32sp) at the user's request.
  static const double homeAction = 32;
  static const double homeActionHeightRatio = 1.35;
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
  static const double dictionaryFilterRow = 32;
  static const double iconSmall = 16;
  static const double icon = 20;
  static const double iconLarge = 24;
  static const double emptyIcon = 40;
  static const double heroIcon = 48;
  static const double homeActionHeight = 72;
  static const double homeActionIcon = 28;
  static const double cameraShutter = 72;
  static const double cameraShutterInner = 58;
  static const double cameraSideControl = 48;
  static const double cameraSideControlWidth = 82;
  static const double captureAction = 52;
  static const double corpusAction = 44;
  static const double cameraProgress = 20;
  static const double corpusPhotoMaxHeight = 420;
  static const double cameraShutterRing = 4;
  static const double capturePhotoHeight = 250;
  static const double capturePhotoMin = 120;
  static const double captureResizeHandle = 40;
  static const double captureResizeBarWidth = 44;
  static const double captureResizeBarHeight = 4;
  static const double captureControlsReserve = 300;
  static const double captureGridBottomReserve = 96;
  static const double pageMaxWidth = 720;
  static const double borderWidth = 1;
}

/// Phase 6 Agent semantic tokens. Values reuse the blue/white palette; the
/// names keep Agent widgets free of hard-coded colors and sizes.
abstract final class AgentTokens {
  static const Color userSurface = AppColors.blue50;
  static const Color assistantSurface = AppColors.surface;
  static const Color evidenceSurface = AppColors.surface;
  static const Color evidenceBorder = AppColors.border;
  static const Color citationSurface = AppColors.blue50;
  static const Color citationText = AppColors.blue700;
  static const Color supplementSurface = AppColors.surfaceMuted;
  static const Color strictBadge = AppColors.header;
  static const Color looseBadge = AppColors.surfaceMuted;

  static const double body = 16;
  static const double helper = 14;
  static const double section = 18;
  static const double evidenceTitle = 16;
  static const double citationChip = 12;
  static const double citationChipHeight = 28;
  static const double stageText = 14;
  static const double badge = 12;
  static const double evidenceRadius = AppRadius.md;
  static const double cardPadding = AppSpacing.md;

  // Conversational Agent v2
  static const double bubbleRadius = AppRadius.xl;
  static const double bubbleTailRadius = 4;
  static const double messageMaxWidth = 0.8;
  static const double modelLabel = 12;
  static const double systemMessage = 14;
  static const double sessionBarHeight = 32;
  static const double statusBarHeight = 24;
  static const int composerMaxLines = 5;
  static const double composerButton = 40;
  static const double imageThumbnail = 64;
  static const double sentImageWidth = 160;
  static const double sentImageHeight = 120;
}

/// Slides a new page in from the right and leaves the previous page in place.
///
/// Deliberately contains no [FadeTransition]: cross-fading made the deep-blue
/// AppBar flash white during navigation. The new page is opaque and physically
/// covers the old one.
class SlideOverPageTransitionsBuilder extends PageTransitionsBuilder {
  const SlideOverPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double>? secondaryAnimation,
    Widget child,
  ) {
    if (route?.isFirst ?? false) return child;
    return SlideTransition(
      position: animation.drive(
        Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
      ),
      child: child,
    );
  }
}

abstract final class AppTheme {
  static ThemeData light({String fontFamily = AppTypography.fontFamily}) {
    final String? family = fontFamily.isEmpty ? null : fontFamily;
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
      fontFamily: family,
      fontFamilyFallback: family == null
          ? null
          : AppTypography.fontFamilyFallback,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.surface,
      visualDensity: VisualDensity.compact,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SlideOverPageTransitionsBuilder(),
          TargetPlatform.fuchsia: SlideOverPageTransitionsBuilder(),
          TargetPlatform.iOS: SlideOverPageTransitionsBuilder(),
          TargetPlatform.linux: SlideOverPageTransitionsBuilder(),
          TargetPlatform.macOS: SlideOverPageTransitionsBuilder(),
          TargetPlatform.windows: SlideOverPageTransitionsBuilder(),
        },
      ),
    );

    final roundedShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.header,
        foregroundColor: AppColors.onHeader,
        surfaceTintColor: AppColors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: AppSizes.appBar,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(
          size: AppSizes.icon,
          color: AppColors.onHeader,
        ),
        titleTextStyle: TextStyle(
          fontFamily: family,
          fontSize: AppTypography.headline,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: AppColors.onHeader,
        ),
        shape: const Border(),
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
          textStyle: WidgetStatePropertyAll(
            TextStyle(
              fontFamily: family,
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
          textStyle: WidgetStatePropertyAll(
            TextStyle(
              fontFamily: family,
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
          textStyle: WidgetStatePropertyAll(
            TextStyle(
              fontFamily: family,
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
        hintStyle: TextStyle(
          fontFamily: family,
          fontSize: AppTypography.headline,
          color: AppColors.textTertiary,
        ),
        labelStyle: TextStyle(
          fontFamily: family,
          fontSize: AppTypography.helper,
          color: AppColors.textSecondary,
        ),
        helperStyle: TextStyle(
          fontFamily: family,
          fontSize: AppTypography.helper,
          height: 1.5,
          color: AppColors.textTertiary,
        ),
        errorStyle: TextStyle(
          fontFamily: family,
          fontSize: AppTypography.helper,
          height: 1.5,
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
        labelStyle: TextStyle(
          fontFamily: family,
          fontSize: AppTypography.title,
          color: AppColors.textPrimary,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: family,
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
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        minVerticalPadding: AppSpacing.sm,
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        titleTextStyle: TextStyle(
          fontFamily: family,
          fontSize: AppTypography.headline,
          height: 1.4,
          color: AppColors.textPrimary,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: family,
          fontSize: AppTypography.helper,
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
        titleTextStyle: TextStyle(
          fontFamily: family,
          fontSize: AppTypography.headline,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontFamily: family,
          fontSize: AppTypography.headline,
          height: AppTypography.textHeight,
          color: AppColors.textPrimary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: TextStyle(
          fontFamily: family,
          fontSize: AppTypography.headline,
          color: Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.onHeader,
        unselectedLabelColor: AppColors.onHeader.withValues(alpha: 0.72),
        indicatorColor: AppColors.onHeader,
        dividerColor: AppColors.transparent,
        labelStyle: TextStyle(
          fontFamily: family,
          fontSize: AppTypography.headline,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: family,
          fontSize: AppTypography.headline,
        ),
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
        textStyle: TextStyle(
          fontFamily: family,
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

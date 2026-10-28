import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/theme/app_fonts.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';

void main() {
  test('theme follows the blue/white specification', () {
    final theme = AppTheme.light();

    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.colorScheme.primary, const Color(0xFF0052D9));
    expect(theme.colorScheme.surface, Colors.white);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.brightness, Brightness.light);
  });

  test('typography uses 24/16/12 logical sizes', () {
    final theme = AppTheme.light();

    expect(theme.textTheme.headlineSmall?.fontSize, 24);
    expect(theme.textTheme.bodyLarge?.fontSize, 16);
    expect(theme.textTheme.bodyMedium?.fontSize, 16);
    expect(theme.textTheme.bodySmall?.fontSize, 12);
    expect(theme.textTheme.labelLarge?.fontSize, 16);
    expect(theme.textTheme.labelSmall?.fontSize, 12);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'HarmonyOS Sans SC');
  });

  test('system font override clears the HarmonyOS family', () {
    final theme = AppTheme.light(fontFamily: AppFonts.system);

    expect(theme.textTheme.bodyMedium?.fontFamily, isNot('HarmonyOS Sans SC'));
  });

  test('home brand header and action buttons follow the revision', () {
    expect(AppColors.header, AppColors.blue700);
    expect(AppColors.onHeader, Colors.white);
    expect(AppSizes.homeActionHeight, 72);
    // Centered content and a 20% smaller label than the first revision.
    expect(AppTypography.homeAction, 32);
    final textLineBox =
        AppTypography.homeAction * AppTypography.homeActionHeightRatio;
    expect(textLineBox, lessThan(AppSizes.homeActionHeight));
  });

  test('every app bar uses the deep blue brand header', () {
    final theme = AppTheme.light();

    expect(theme.appBarTheme.backgroundColor, AppColors.header);
    expect(theme.appBarTheme.foregroundColor, AppColors.onHeader);
    expect(theme.appBarTheme.titleTextStyle?.color, AppColors.onHeader);
    expect(theme.appBarTheme.iconTheme?.color, AppColors.onHeader);
    expect(theme.tabBarTheme.labelColor, AppColors.onHeader);
    expect(theme.tabBarTheme.indicatorColor, AppColors.onHeader);
  });

  test('readability tokens are enlarged', () {
    final theme = AppTheme.light();

    expect(AppTypography.helper, 14);
    expect(AppTypography.sectionHeading, 18);
    expect(AppTypography.entryTitle, 24);
    expect(theme.listTileTheme.subtitleTextStyle?.fontSize, 14);
    expect(theme.inputDecorationTheme.helperStyle?.fontSize, 14);
  });

  test('components are compact', () {
    final theme = AppTheme.light();

    expect(theme.visualDensity, VisualDensity.compact);
    expect(theme.appBarTheme.toolbarHeight, AppSizes.appBar);
    expect(
      theme.filledButtonTheme.style?.minimumSize?.resolve({}),
      const Size(64, AppSizes.control),
    );
    expect(AppRadius.lg, 12);
  });

  test('spacing scale is 4pt based', () {
    expect(AppSpacing.xxs, 2);
    for (final value in [
      AppSpacing.xs,
      AppSpacing.sm,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.xl,
      AppSpacing.xxl,
    ]) {
      expect(value % 4, 0);
    }
    expect(AppTypography.display, AppTypography.displayDesignPx / 3);
    expect(AppTypography.headline, AppTypography.headlineDesignPx / 3);
    expect(AppTypography.title, AppTypography.titleDesignPx / 3);
  });
}

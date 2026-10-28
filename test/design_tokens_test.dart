import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// Full-photo canvas shared by the photo set and corpus detail pages.
///
/// When [onHeightChanged] is supplied, the bottom edge becomes draggable and
/// the handle is a single-colour white bar (no pill/outline).
class PhotoPane extends StatelessWidget {
  const PhotoPane({
    super.key,
    required this.imagePath,
    required this.height,
    required this.maxHeight,
    required this.onTap,
    this.onHeightChanged,
    this.overlays = const [],
  });

  final String imagePath;
  final double height;
  final double maxHeight;
  final VoidCallback onTap;
  final ValueChanged<double>? onHeightChanged;
  final List<Widget> overlays;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            button: true,
            label: '查看照片',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: ColoredBox(
                color: AppColors.surfaceMuted,
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Center(child: Text('无法显示照片')),
                ),
              ),
            ),
          ),
          if (onHeightChanged != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: AppSizes.captureResizeHandle,
              child: Semantics(
                label: '调整照片显示范围',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {
                    onHeightChanged!(
                      (height + details.delta.dy)
                          .clamp(AppSizes.capturePhotoMin, maxHeight)
                          .toDouble(),
                    );
                  },
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: AppSizes.captureResizeBarWidth,
                      height: AppSizes.captureResizeBarHeight,
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.cameraControl,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ...overlays,
        ],
      ),
    );
  }
}

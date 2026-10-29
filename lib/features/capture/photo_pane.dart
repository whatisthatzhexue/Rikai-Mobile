import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// Full-photo canvas shared by the photo set and corpus detail pages.
///
/// When [onHeightChanged] is supplied, the bottom edge becomes draggable and
/// the handle is a single-colour white bar (no pill/outline). Pointer events
/// are used directly instead of a vertical-drag recognizer so the photo edge
/// follows the finger from the first pixel rather than after the drag slop.
class PhotoPane extends StatefulWidget {
  const PhotoPane({
    super.key,
    required this.imagePath,
    required this.height,
    required this.maxHeight,
    required this.onTap,
    this.onHeightChanged,
    this.overlays = const [],
    this.imageRevision,
  });

  final String imagePath;
  final double height;
  final double maxHeight;
  final VoidCallback onTap;
  final ValueChanged<double>? onHeightChanged;
  final List<Widget> overlays;

  /// Changes when the file at [imagePath] is overwritten (for example after
  /// an in-place 90° rotation). Using it as the Image key bypasses Flutter's
  /// path-based image cache immediately.
  final Object? imageRevision;

  @override
  State<PhotoPane> createState() => _PhotoPaneState();
}

class _PhotoPaneState extends State<PhotoPane> {
  int? _pointer;
  double? _pointerStartY;
  double? _dragStartHeight;

  void _onPointerDown(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _pointerStartY = event.position.dy;
    _dragStartHeight = widget.height;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final startY = _pointerStartY;
    final startHeight = _dragStartHeight;
    final onHeightChanged = widget.onHeightChanged;
    if (startY == null || startHeight == null || onHeightChanged == null) {
      return;
    }
    final next = startHeight + event.position.dy - startY;
    onHeightChanged(
      next.clamp(AppSizes.capturePhotoMin, widget.maxHeight).toDouble(),
    );
  }

  void _endDrag(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _pointerStartY = null;
    _dragStartHeight = null;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            button: true,
            label: '查看照片',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: ColoredBox(
                color: AppColors.surfaceMuted,
                child: Image.file(
                  File(widget.imagePath),
                  key: ValueKey('${widget.imagePath}-${widget.imageRevision}'),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Center(child: Text('无法显示照片')),
                ),
              ),
            ),
          ),
          if (widget.onHeightChanged != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: AppSizes.captureResizeHandle,
              child: Semantics(
                label: '调整照片显示范围',
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _endDrag,
                  onPointerCancel: _endDrag,
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
          ...widget.overlays,
        ],
      ),
    );
  }
}

import 'package:flutter/widgets.dart';

/// Decodes an Agent thumbnail at display resolution instead of the full photo.
///
/// A full-resolution `Image.file` inside a lazily built list can hitch for a
/// frame when it first enters the viewport. Agent photos stay local; only the
/// decode target changes.
int agentThumbnailCacheSize(BuildContext context, double logicalSize) {
  final ratio = MediaQuery.devicePixelRatioOf(context);
  return (logicalSize * ratio).ceil();
}

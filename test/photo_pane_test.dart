import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/theme/app_tokens.dart';
import 'package:lexicandy/features/capture/photo_pane.dart';

void main() {
  testWidgets('a collapsed photo pane hides the image but keeps the handle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: PhotoPane(
            imagePath: '/nonexistent/photo.jpg',
            height: 0,
            maxHeight: 300,
            onTap: () {},
            onHeightChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(
      tester.getSize(find.byType(PhotoPane)).height,
      AppSizes.captureResizeHandle,
    );
  });
}

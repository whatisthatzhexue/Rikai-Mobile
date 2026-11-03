import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_pitch.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/agent/agent_pitch_accent.dart';

void main() {
  testWidgets('pitch line stays above the ruby reading and base', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(
            child: AgentPitchAccentText(
              surface: '橋',
              reading: 'はし',
              accent: AgentPitchAccent(
                accentType: 2,
                moraCount: 2,
                moraPattern: 'LH',
              ),
              style: TextStyle(fontSize: 16, color: AppColors.textPrimary),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pitchY = tester
        .getTopLeft(
          find.descendant(
            of: find.byType(AgentPitchAccentText),
            matching: find.byType(CustomPaint),
          ),
        )
        .dy;
    final rubyY = tester.getTopLeft(find.text('はし')).dy;
    final baseY = tester.getTopLeft(find.text('橋')).dy;
    expect(pitchY, lessThan(rubyY));
    expect(rubyY, lessThan(baseY));
  });

  testWidgets('pitch overlay does not increase the inline word height', (
    tester,
  ) async {
    Future<double> heightFor(AgentPitchAccent? accent) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: AgentPitchAccentText(
                surface: '橋',
                reading: 'はし',
                accent: accent,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(AgentPitchAccentText)).height;
    }

    final withoutPitch = await heightFor(null);
    final withPitch = await heightFor(
      const AgentPitchAccent(accentType: 2, moraCount: 2, moraPattern: 'LH'),
    );
    expect(withPitch, closeTo(withoutPitch, 0.1));
  });

  testWidgets('kanji without a distinct reading hides the pitch line', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: AgentPitchAccentText(
            surface: '橋',
            reading: '',
            accent: AgentPitchAccent(
              accentType: 2,
              moraCount: 2,
              moraPattern: 'LH',
            ),
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('橋'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AgentPitchAccentText),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets('kana without a reading may still show the pitch line', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: AgentPitchAccentText(
            surface: 'はし',
            reading: '',
            accent: AgentPitchAccent(
              accentType: 2,
              moraCount: 2,
              moraPattern: 'LH',
            ),
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AgentPitchAccentText),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no pitch line is drawn without valid accent data', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: AgentPitchAccentText(
            surface: '橋',
            reading: 'はし',
            accent: null,
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('橋'), findsOneWidget);
    expect(find.text('はし'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AgentPitchAccentText),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });
}

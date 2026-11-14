import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/agent/agent_pitch.dart';
import 'package:lexicandy/core/theme/app_tokens.dart';
import 'package:lexicandy/features/agent/agent_pitch_accent.dart';

Finder _pitchLayout() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_PitchAccentLayout',
);

void main() {
  testWidgets('pitch layout keeps ruby above base and reports a baseline', (
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

    expect(_pitchLayout(), findsOneWidget);
    final rubyY = tester.getTopLeft(find.text('はし')).dy;
    final baseY = tester.getTopLeft(find.text('橋')).dy;
    expect(rubyY, lessThan(baseY));
  });

  testWidgets('pitch word aligns to a neighbouring text baseline', (
    tester,
  ) async {
    const style = TextStyle(fontSize: 16);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text('あ', style: style),
              AgentPitchAccentText(
                surface: '橋',
                reading: 'はし',
                accent: AgentPitchAccent(
                  accentType: 2,
                  moraCount: 2,
                  moraPattern: 'LH',
                ),
                style: style,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final reference = tester.renderObject<RenderBox>(find.text('あ'));
    final base = tester.renderObject<RenderBox>(find.text('橋'));
    final referenceBaseline =
        tester.getRect(find.text('あ')).top +
        (reference.getDryBaseline(
              reference.constraints,
              TextBaseline.alphabetic,
            ) ??
            0);
    final baseBaseline =
        tester.getRect(find.text('橋')).top +
        (base.getDryBaseline(base.constraints, TextBaseline.alphabetic) ?? 0);
    expect(baseBaseline, closeTo(referenceBaseline, 0.01));
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
    expect(_pitchLayout(), findsNothing);
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

    expect(_pitchLayout(), findsOneWidget);
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
    expect(_pitchLayout(), findsNothing);
  });

  test('odaka draws the drop after the final mora', () {
    const accent = AgentPitchAccent(
      accentType: 3,
      moraCount: 3,
      moraPattern: 'LHH',
    );
    final segments = pitchAccentSegments(
      accent: accent,
      size: const Size(90, 8),
      strokeWidth: 1.5,
    );
    expect(
      segments.any(
        (segment) =>
            segment.start.dx == segment.end.dx &&
            segment.start.dx == 90 &&
            segment.start.dy != segment.end.dy,
      ),
      isTrue,
    );
  });

  test('heiban does not draw an end drop', () {
    const accent = AgentPitchAccent(
      accentType: 0,
      moraCount: 3,
      moraPattern: 'LHH',
    );
    final segments = pitchAccentSegments(
      accent: accent,
      size: const Size(90, 8),
      strokeWidth: 1.5,
    );
    expect(
      segments.any(
        (segment) =>
            segment.start.dx == segment.end.dx && segment.start.dx > 88,
      ),
      isFalse,
    );
  });
}

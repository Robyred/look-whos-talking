import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_whos_talking/models/job_result.dart';
import 'package:look_whos_talking/screens/results_screen.dart';

DiarizationResult _result() => const DiarizationResult(
      filename: 'team meeting.m4a',
      totalDurationSec: 120,
      speakerCount: 1,
      speakers: [
        SpeakerResult(speakerId: 'SPEAKER_00', durationSec: 120, percentage: 100),
      ],
      overlapSec: 0,
      speechSec: 120,
      silenceSec: 0,
      transcript: [
        TranscriptSegment(
          speakerId: 'SPEAKER_00',
          start: 0,
          end: 2,
          text: 'Hello there',
        ),
      ],
    );

void main() {
  testWidgets('Transcript tab exposes a share action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen(jobId: 'job_1', result: _result()),
      ),
    );
    await tester.pumpAndSettle();

    // Overview is the default tab.
    expect(find.text('Share metrics'), findsOneWidget);

    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();

    expect(find.text('Share transcript'), findsOneWidget);
  });
}

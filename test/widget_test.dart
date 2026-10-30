// Smoke test mac dinh: app build duoc khong crash.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:truyen_audio_app/main.dart';

void main() {
  testWidgets('TruyenAudioApp build smoke test', (WidgetTester tester) async {
    // Build app that va trigger frame.
    await tester.pumpWidget(const ProviderScope(child: TruyenAudioApp()));
    await tester.pump();

    // App vao duoc (MaterialApp.router hien 1 man hinh).
    expect(find.byType(TruyenAudioApp), findsOneWidget);
  });
}

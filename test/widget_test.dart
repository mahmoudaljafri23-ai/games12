import 'package:flutter_test/flutter_test.dart';
import 'package:projectgoogl/main.dart';

void main() {
  testWidgets('Smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const VoiceDeceptionGameApp());

    // Verify that the login title exists
    expect(find.text('لعبة الصورة الخفية'), findsOneWidget);
  });
}

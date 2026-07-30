import 'package:flutter_test/flutter_test.dart';
import 'package:motion_box/main.dart';

void main() {
  testWidgets('Motion Box layout smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MotionBoxApp());

    // Verify that the title logo "MOTION BOX" is present in the app bar.
    expect(find.text('MOTION BOX'), findsOneWidget);

    // Verify that the initial filter chip options render.
    expect(find.text('Ready Templates'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
  });
}

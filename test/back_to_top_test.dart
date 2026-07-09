import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/widgets/back_to_top.dart';

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BackToTop(
          builder: (context, controller) => ListView.builder(
            controller: controller,
            itemCount: 100,
            itemBuilder: (_, i) => SizedBox(height: 80, child: Text('row $i')),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // Issue #25: an arrow at the bottom of long lists jumps back to the top.
  test('showBackToTop trips only past the threshold', () {
    expect(showBackToTop(0), isFalse);
    expect(showBackToTop(kBackToTopThreshold), isFalse);
    expect(showBackToTop(kBackToTopThreshold + 1), isTrue);
  });

  testWidgets('button appears after scrolling down and returns to top', (
    tester,
  ) async {
    await _pump(tester);

    // At the top the button is hidden (transparent and untappable).
    Finder button() => find.byType(FloatingActionButton);
    AnimatedOpacity opacityOf(Finder f) => tester.widget<AnimatedOpacity>(
      find.ancestor(of: f, matching: find.byType(AnimatedOpacity)),
    );
    expect(opacityOf(button()).opacity, 0);

    // Scroll well past the threshold — the button fades in.
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(opacityOf(button()).opacity, 1);
    expect(find.text('row 0'), findsNothing);

    // Tapping it scrolls smoothly back to the top and hides the button again.
    await tester.tap(button());
    await tester.pumpAndSettle();
    expect(find.text('row 0'), findsOneWidget);
    expect(opacityOf(button()).opacity, 0);
  });
}

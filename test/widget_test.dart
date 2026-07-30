import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protrading/main.dart';

void main() {
  testWidgets('App starts without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ProTradingApp()),
    );
    expect(find.text('종목'), findsWidgets);
  });
}

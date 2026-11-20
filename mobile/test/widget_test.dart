// Basic smoke test for MiniBike Stats app.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:minibike_stats/main.dart';
import 'package:minibike_stats/services/minibike_ble.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    // Build our app wrapped with the required Provider and trigger a frame.
    await tester.pumpWidget(
      ChangeNotifierProvider<MiniBikeBle>(
        create: (_) => MiniBikeBle(),
        child: const MiniBikeStatsApp(),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Мой самокат'), findsOneWidget);

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Единицы измерения'), findsOneWidget);

    await tester.tap(find.text('Админ'));
    await tester.pumpAndSettle();
    expect(find.text('Пароль'), findsOneWidget);
  });
}

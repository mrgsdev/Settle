import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settle/main.dart';
import 'package:settle/model/budget.dart';
import 'package:settle/model/store.dart';

import 'demo_data.dart';
import 'test_fonts.dart';

void main() {
  Future<BudgetStore> openExpenses(WidgetTester tester) async {
    await tester.runAsync(loadTestFonts);
    tester.view.physicalSize = const Size(1440, 2300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = BudgetStore.memory(demoData());
    await tester.pumpWidget(SettleApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Расходы').first);
    await tester.pumpAndSettle();
    return store;
  }

  /// Ввод «с клавиатуры» после одного щелчка — как в настоящем окне.
  Future<void> typeAfterOneClick(
    WidgetTester tester,
    Finder cell,
    String text,
  ) async {
    await tester.tap(cell);
    await tester.pumpAndSettle();
    tester.testTextInput.enterText(text);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets('ячейка с формулой редактируется с первого щелчка', (
    tester,
  ) async {
    final store = await openExpenses(tester);
    // 1 сентября: «=6500+1200» показывается как «7 700 ₽».
    await typeAfterOneClick(
      tester,
      find.widgetWithText(TextField, '7 700 ₽').first,
      '=1000+1',
    );
    expect(store.data.expenses.days[0].amount, '=1000+1');

    // Обычная ячейка — тоже с первого щелчка.
    await typeAfterOneClick(
      tester,
      find.widgetWithText(TextField, '1 180 ₽'),
      '990',
    );
    expect(store.data.expenses.days[6].amount, '990');
  });

  testWidgets('в сумме — только цифры и знаки арифметики', (tester) async {
    final store = await openExpenses(tester);
    final day = store.data.expenses.days[6]; // «Аптека», 1180
    await tester.tap(find.widgetWithText(TextField, '1 180 ₽'));
    await tester.pumpAndSettle();
    final editor = find.widgetWithText(TextField, '1180');

    // Буквы и «=» не в начале не вводятся: остаётся прежний текст.
    for (final bad in ['1212=50+40', '12abc', '5%', 'сто']) {
      tester.testTextInput.enterText(bad);
      await tester.pump();
      expect(editor, findsOneWidget, reason: bad);
    }

    // Выражение без «=» становится формулой.
    tester.testTextInput.enterText('50 + 40');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(day.amount, '=50+40');
    expect(find.widgetWithText(TextField, '90 ₽'), findsWidgets);

    // Формула с ошибкой: Enter не принимает, поле остаётся открытым.
    await tester.tap(find.widgetWithText(TextField, '90 ₽').first);
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('=5++');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(day.amount, '=50+40');
    expect(find.widgetWithText(TextField, '=5++'), findsOneWidget);
    // Уход из поля — значение не меняется, показывается подсказка.
    await tester.tap(find.text('Расходы').first);
    await tester.pumpAndSettle();
    expect(day.amount, '=50+40');
    expect(find.textContaining('Не получилось посчитать'), findsOneWidget);
    expect(find.widgetWithText(TextField, '=5++'), findsNothing);
  });

  testWidgets('обзор: выбор месяца, когда их много', (tester) async {
    await tester.runAsync(loadTestFonts);
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = demoData();
    data.months = [
      for (var i = 0; i < 30; i++)
        BalanceMonth(
          title: '',
          date: DateTime(2028, 9 + i),
          sources: [BalanceSource(name: 'Карта', balance: '${1000 + i}')],
        ),
    ];
    await tester.pumpWidget(SettleApp(store: BudgetStore.memory(data)));
    await tester.pumpAndSettle();
    expect(find.text('Февраль 2031'), findsOneWidget); // последний месяц

    // Первый выбор — месяцы (второй — годы в «Динамике»).
    await tester.tap(find.byTooltip('Раньше').first);
    await tester.pumpAndSettle();
    expect(find.text('Январь 2031'), findsOneWidget);

    // Любой месяц — из списка, в том числе самый старый.
    await tester.tap(find.text('Январь 2031'));
    await tester.pumpAndSettle();
    // Список меню — последний прокручиваемый элемент на экране.
    await tester.scrollUntilVisible(
      find.text('Сентябрь 2028'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Сентябрь 2028'));
    await tester.pumpAndSettle();
    expect(find.text('Сентябрь 2028'), findsOneWidget);
    expect(find.text('1 000,00 ₽'), findsWidgets);
    // Самый старый месяц: «Раньше» больше некуда.
    final back = find
        .ancestor(
          of: find.byIcon(Icons.chevron_left_rounded),
          matching: find.byType(IconButton),
        )
        .first;
    expect(tester.widget<IconButton>(back).onPressed, isNull);
  });
}

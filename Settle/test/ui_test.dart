import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settle/main.dart';
import 'package:settle/model/store.dart';

import 'demo_data.dart';
import 'test_fonts.dart';

void main() {
  Future<BudgetStore> launch(WidgetTester tester) async {
    await tester.runAsync(loadTestFonts);
    tester.view.physicalSize = const Size(1440, 2300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = BudgetStore.memory(demoData());
    await tester.pumpWidget(SettleApp(store: store));
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('ввод суммы формулой в ячейку дня', (tester) async {
    final store = await launch(tester);
    await tester.tap(find.text('Расходы').first);
    await tester.pumpAndSettle();

    // Ячейка суммы у «Аптека» (7 сентября): показывает «1 180 ₽», в фокусе — «1180».
    final amount = find.widgetWithText(TextField, '1\u00A0180 ₽');
    expect(amount, findsOneWidget);
    await tester.tap(amount);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '1180'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '1180'),
      '= 1000 + 500,5',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final day = store.data.expenses.days[6];
    expect(day.amount, '=1000+500.5');
    expect(store.data.expenses.total.number, 40700 - 1180 + 1500.5);
    expect(find.widgetWithText(TextField, '1\u00A0500,50 ₽'), findsOneWidget);

    // Esc отменяет правку.
    await tester.tap(find.widgetWithText(TextField, 'Аптека'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Аптека'),
      'Что-то другое',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(day.name, 'Аптека');
  });

  testWidgets('переход к следующему месяцу и отмена', (tester) async {
    final store = await launch(tester);
    await tester.tap(find.text('Расходы').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('К октябрю'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Записать итог 40\u00A0700 ₽'), findsOneWidget);
    await tester.tap(find.text('Перейти'));
    await tester.pumpAndSettle();

    final e = store.data.expenses;
    expect((e.year, e.month, e.days.length), (2026, 10, 31));
    expect(e.prevRemainder, '9300');
    expect(e.budget, '=50000');
    expect(e.mandatory.first.fact, '');
    expect(store.data.dynamics.years[1].values[8], '40700');
    expect(e.monthTitle, 'Октябрь 2026');

    // Название месяца можно переименовать (у поля и текст, и подсказка —
    // «Октябрь 2026», поэтому .first).
    final title = find.widgetWithText(TextField, 'Октябрь 2026').first;
    await tester.tap(title);
    await tester.pumpAndSettle();
    await tester.enterText(title, 'Октябрь 2026 — отпуск');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(store.data.expenses.monthTitle, 'Октябрь 2026 — отпуск');

    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(store.data.expenses.month, 9);
    expect(store.data.dynamics.years[1].values[8], '');
  });

  testWidgets('новый месяц баланса и долг', (tester) async {
    final store = await launch(tester);
    await tester.tap(find.text('Баланс').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новый месяц'));
    await tester.pumpAndSettle();
    final m = store.data.months.last;
    expect(m.date, DateTime(2026, 10, 1));
    expect(m.title, 'Октябрь 2026');
    expect(m.sources.map((s) => s.name), [
      'Visa',
      'Карта Тинькофф',
      'Наличные',
      'Кошелек',
      'Крипта',
    ]);
    expect(m.sources.every((s) => s.balance.isEmpty), isTrue);
    // Итого нового месяца — 0: «Изменение в %» показывает 0, а не #ДЕЛ/0!.
    expect(store.data.change(3)!.number, 0);
    expect(find.text('0,00 %'), findsOneWidget);
    expect(find.textContaining('#'), findsNothing);

    await tester.tap(find.text('Долги').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить долг').first);
    await tester.pumpAndSettle();
    expect(store.data.debts.length, 4);
    expect(tester.takeException(), isNull);
  });
}

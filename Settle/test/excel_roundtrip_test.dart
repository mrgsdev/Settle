import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settle/excel/budget_excel.dart';
import 'package:settle/model/budget.dart';
import 'package:settle/model/calc.dart';

void main() {
  test('арифметика ячеек', () {
    expect(Raw.eval('=50000')!.number, 50000);
    expect(Raw.eval('=1500+300*2')!.number, 2100);
    expect(Raw.eval('=(10-4)/2')!.number, 3);
    expect(Raw.eval('=10%')!.number, closeTo(0.1, 1e-12));
    expect(Raw.eval('=1/0')!.number, 0);
    expect(Raw.eval('1 234,5')!.number, 1234.5);
    expect(Raw.eval('abc'), isNull);
    expect(Raw.normalize(' = 100,5 + 2 '), '=100.5+2');
    expect(Raw.normalize('1 500'), '1500');
    expect(Raw.sum(['1', '', 'x', '=2*3']).number, 7);
    expect(Raw.average(['', '']).number, 0);
  });

  test('пустой шаблон на текущий месяц', () {
    final tpl = BudgetData.template(DateTime(2026, 10, 15));
    expect(tpl.months.single.title, 'Октябрь 2026');
    expect(tpl.months.single.date, DateTime(2026, 10, 1));
    expect(tpl.months.single.sources.single.name, '');
    expect(tpl.months.single.total.number, 0);
    expect(tpl.shares.every((s) => s.amount.isEmpty), isTrue);
    expect(tpl.sharesShareTotal.number, 0);
    expect(tpl.expenses.monthTitle, 'Октябрь 2026');
    expect(tpl.expenses.days.length, 31);
    expect(tpl.expenses.days.every((d) => d.isEmpty), isTrue);
    expect(tpl.expenses.budget, '');
    expect(tpl.expenses.mandatory.every((m) => m.plan.isEmpty), isTrue);
    expect(tpl.dynamics.years.single.year, 2026);
    expect(tpl.dynamics.years.single.average.number, 0);
    expect(tpl.debts, isEmpty);
  });

  test('шаблон: экспорт → импорт без потерь', () {
    final tpl = BudgetData.template();
    final bytes = BudgetExcel.export(tpl);
    final out = Platform.environment['KT_OUT'];
    if (out != null) File('$out/template_export.xlsx').writeAsBytesSync(bytes);
    final back = BudgetExcel.import(bytes);
    expect(back.warnings, isEmpty);
    expect(jsonEncode(back.data.toJson()), jsonEncode(tpl.toJson()));
  });

  final original = File('/Users/mrgsdev/Desktop/Бюджет.xlsx');
  test('импорт исходного Бюджет.xlsx', () {
    final r = BudgetExcel.import(original.readAsBytesSync());
    final d = r.data;
    expect(r.warnings, isEmpty);
    expect(d.months.length, 2);
    // Названия месяцев берутся из файла как есть.
    expect(d.months[0].title, 'Сентябрь (2026 год) - девиз месяца');
    expect(d.months[0].date, DateTime(2026, 9, 1));
    expect(d.months[0].sources.map((s) => s.name), [
      'Visa',
      'Карта Тинькофф',
      'Наличные',
      'Кошелек',
      'Крипта',
    ]);
    expect(d.months[0].total.number, 240);
    expect(d.months[1].total.number, 0);
    expect(d.saldo(1)!.number, -240);
    expect(d.change(1)!.number, 0);
    expect(d.shares.map((s) => s.label), [
      'Потребление',
      'Инвестиции',
      'Сбережения',
    ]);
    expect(d.expenses.monthTitle, 'Октябрь');
    expect(d.expenses.days.length, 31);
    expect(d.expenses.days.first.name, 'Транспорт + ЖКХ');
    expect(d.expenses.budget, '=50000');
    expect(d.expenses.remainder.number, 50000);
    expect(d.expenses.mandatory.length, 6);
    expect(d.dynamics.years.map((y) => y.year), [2025, 2026]);
    expect(d.debts, isEmpty);

    // Повторный экспорт
    final bytes = BudgetExcel.export(d);
    final out = Platform.environment['KT_OUT'];
    if (out != null) File('$out/reexport.xlsx').writeAsBytesSync(bytes);
  }, skip: !original.existsSync());

  test('данные с формулами и долгами', () {
    final d = BudgetData.template(DateTime(2026, 10));
    d.months[0].sources
      ..[0].name = 'Карта'
      ..[0].balance = '=100+50'
      ..add(BalanceSource(name: 'Наличные', balance: '300'));
    d.expenses.days[4].amount = '=1500+300';
    d.expenses.days[4].name = 'Продукты';
    d.expenses.prevRemainder = '1200';
    d.expenses.budget = '=50000';
    d.expenses.mandatory[0].plan = '5000';
    d.expenses.mandatory[0].fact = '4800';
    d.dynamics.years[0].values[8] = '41000';
    d.shares[0].amount = '150';
    d.shares[2].amount = '30';
    d.debts.addAll([
      Debt(
        date: '05.10.2026',
        amount: '15000',
        creditor: 'Иван',
        purpose: 'Ремонт',
      ),
      Debt(
        date: 'когда-то',
        amount: '=2000*2',
        creditor: 'Банк',
        purpose: 'Кредит',
      ),
      Debt(amount: '700', creditor: 'Аня'),
      Debt(amount: '100', creditor: 'Петя', purpose: 'Кофе'),
    ]);
    final bytes = BudgetExcel.export(d);
    final out = Platform.environment['KT_OUT'];
    if (out != null) File('$out/filled_export.xlsx').writeAsBytesSync(bytes);
    final back = BudgetExcel.import(bytes).data;
    expect(jsonEncode(back.toJson()), jsonEncode(d.toJson()));
    expect(back.debtTotal.number, 19800);
    expect(back.expenses.total.number, 1800);
    expect(back.months[0].total.number, 450);
  });

  test('деление на ноль в Excel — IFERROR(…;0), как в приложении', () {
    final d = BudgetData.template(DateTime(2026, 10));
    d.months.add(
      BalanceMonth(
        title: 'Ноябрь 2026',
        date: DateTime(2026, 11),
        sources: [BalanceSource()],
      ),
    );
    final sheet = utf8.decode(
      ZipDecoder()
          .decodeBytes(BudgetExcel.export(d))
          .findFile('xl/worksheets/sheet1.xml')!
          .content,
    );
    expect(sheet, contains('<f>IFERROR((C'));
    expect(sheet, contains('<f>IFERROR(I3/I'));
    expect(sheet, isNot(contains('#DIV/0!')));
  });
}

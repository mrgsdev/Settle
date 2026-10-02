import 'dart:typed_data';

import '../model/budget.dart';
import '../model/calc.dart';
import 'xlsx_reader.dart';
import 'xlsx_writer.dart';

/// Перевод модели в книгу «Бюджет.xlsx» и обратно.
///
/// Раскладка ячеек, стили, ширины колонок и формулы повторяют исходный файл:
/// • Баланс — блоки месяцев по 11 строк с шагом 13, сводка «Статья/Сумма/Доля» в H2:J6;
/// • Расходы — дни месяца с 3-й строки, Итого/Остаток/Бюджет, обязательные расходы в F:H;
/// • Динамика — месяцы × годы, «Итого» = AVERAGE;
/// • Долги — таблица долгов и «Общий долг».
///
/// Формулы с делением обёрнуты в IFERROR(…;0): как и в приложении, при делении
/// на ноль Excel покажет 0, а не #ДЕЛ/0!.
class BudgetExcel {
  BudgetExcel._();

  // ───────────────────────────── Экспорт ─────────────────────────────

  static Uint8List export(BudgetData d) {
    final w = XlsxWriter();
    _balance(w.addSheet('Баланс')..selected = true, d);
    _expenses(w.addSheet('Расходы'), d.expenses);
    _dynamics(w.addSheet('Динамика'), d.dynamics);
    _debts(w.addSheet('Долги'), d);
    return w.build();
  }

  static XCell _text(String text, int style) => XCell(style: style, text: text);

  static XCell _formula(String formula, CalcValue v, int style) =>
      XCell(style: style, formula: formula, number: v.number, error: v.error);

  /// Ячейка ввода: пусто, число, текст или арифметическая формула пользователя.
  static XCell _raw(String raw, int style) {
    final s = raw.trim();
    if (s.isEmpty) return XCell.empty(style);
    if (Raw.isFormula(s)) {
      final v = Raw.eval(s);
      return XCell(
        style: style,
        formula: s.substring(1),
        number: v?.number,
        error: v?.error,
      );
    }
    final n = Raw.parseNumber(s);
    if (n != null) return XCell(style: style, number: n);
    return XCell(style: style, text: s);
  }

  static int _articleStyle(String article) {
    final a = article.trim().toLowerCase();
    if (a.startsWith('потреб')) return XStyle.fillOrange;
    if (a.startsWith('сбереж')) return XStyle.fillBlue;
    return XStyle.text;
  }

  static void _balance(XSheet s, BudgetData d) {
    s.colWidths.addAll({
      1: 17.7109375,
      2: 15.5703125,
      3: 14.5703125,
      4: 16.42578125,
      8: 17.42578125,
      9: 14.7109375,
      10: 15.28515625,
    });

    var r = 1;
    int? prevTotalRow;
    for (var i = 0; i < d.months.length; i++) {
      final m = d.months[i];

      // Заголовок «Октябрь 2026» и дата — объединённые A:D.
      s.set(r, 1, _text(m.title, XStyle.monthTitle));
      for (var c = 2; c <= 4; c++) {
        s.set(r, c, const XCell.empty(XStyle.monthTitle));
      }
      s.merge(r, 1, r, 4);
      s.set(
        r + 1,
        1,
        XCell(style: XStyle.monthDate, number: excelSerial(m.date)),
      );
      for (var c = 2; c <= 4; c++) {
        s.set(r + 1, c, const XCell.empty(XStyle.monthDate));
      }
      s.merge(r + 1, 1, r + 1, 4);

      final h = r + 2;
      s.set(h, 1, _text('Источник', XStyle.headerBold));
      s.set(h, 2, _text('Валюта', XStyle.headerBold));
      s.set(h, 3, _text('Баланс', XStyle.headerBold));
      s.set(h, 4, _text('Статья', XStyle.headerBold2));

      final sources = m.sources.isEmpty
          ? [BalanceSource(currency: '', article: '')]
          : m.sources;
      var row = h + 1;
      final first = row;
      for (final src in sources) {
        s.set(row, 1, _text(src.name, XStyle.text3));
        s.set(row, 2, _text(src.currency, XStyle.text));
        s.set(row, 3, _raw(src.balance, XStyle.money));
        s.set(row, 4, _text(src.article, _articleStyle(src.article)));
        row++;
      }
      final last = row - 1;
      final t = row;

      s.set(t, 1, _text('Итого', XStyle.headerBold));
      s.set(t, 2, const XCell.empty(XStyle.text));
      s.set(t, 3, _formula('SUM(C$first:C$last)', m.total, XStyle.moneyBold));
      s.set(t, 4, const XCell.empty(XStyle.textPlain));

      s.set(t + 1, 1, _text('Сальдо', XStyle.headerBold2));
      s.set(t + 1, 2, const XCell.empty(XStyle.borderOnly));
      s.set(
        t + 1,
        3,
        prevTotalRow == null
            ? const XCell.empty(XStyle.moneyBlue)
            : _formula('C$t-C$prevTotalRow', d.saldo(i)!, XStyle.moneyBlue),
      );
      s.set(t + 1, 4, const XCell.empty(XStyle.textPlain));

      s.set(t + 2, 1, _text('Изменение в %', XStyle.headerBold2));
      s.set(t + 2, 2, const XCell.empty(XStyle.borderOnly));
      s.set(
        t + 2,
        3,
        prevTotalRow == null
            ? const XCell.empty(XStyle.percentOrange)
            : _formula(
                'IFERROR((C$t-C$prevTotalRow)/C$t,0)',
                d.change(i)!,
                XStyle.percentOrange,
              ),
      );
      s.set(t + 2, 4, const XCell.empty(XStyle.borderOnly));

      prevTotalRow = t;
      r = t + 3 + 2; // две пустые строки между блоками
    }

    // Сводка «Статья · Сумма · Доля» (H2:J6).
    final shares = d.shares.isEmpty ? BudgetData.defaultShares() : d.shares;
    final calc = BudgetData(
      months: [],
      shares: shares,
      expenses: d.expenses,
      dynamics: d.dynamics,
      debts: [],
    );
    s.set(2, 8, _text('Статья', XStyle.fillOrange));
    s.set(2, 9, _text('Сумма', XStyle.fillOrange));
    s.set(2, 10, _text('Доля', XStyle.fillOrange));
    final totalRow = 3 + shares.length;
    for (var i = 0; i < shares.length; i++) {
      final row = 3 + i;
      s.set(row, 8, _text(shares[i].label, XStyle.text));
      s.set(row, 9, _raw(shares[i].amount, XStyle.moneyCenter));
      s.set(
        row,
        10,
        _formula(
          'IFERROR(I$row/I$totalRow,0)',
          calc.shareOf(i),
          XStyle.percent,
        ),
      );
    }
    s.set(totalRow, 8, _text('Итого', XStyle.headerBold));
    s.set(
      totalRow,
      9,
      _formula(
        'SUM(I3:I${totalRow - 1})',
        calc.sharesTotal,
        XStyle.moneyBoldCenter,
      ),
    );
    s.set(
      totalRow,
      10,
      _formula(
        'SUM(J3:J${totalRow - 1})',
        calc.sharesShareTotal,
        XStyle.percentBold,
      ),
    );
  }

  static void _expenses(XSheet s, ExpenseSheet e) {
    s.zoom = 85;
    s.colWidths.addAll({
      1: 11.85546875,
      2: 16.85546875,
      3: 11.85546875,
      4: 14.42578125,
      5: 21.28515625,
      6: 26.42578125,
    });

    s.set(1, 1, _text(e.monthTitle, XStyle.expHeaderMonth));
    s.set(2, 1, const XCell.empty(XStyle.expHeaderMonth2));
    s.merge(1, 1, 2, 1);
    const heads = ['Наименование', 'Сумма', 'Примечание'];
    for (var i = 0; i < heads.length; i++) {
      s.set(1, 2 + i, _text(heads[i], XStyle.expHeader));
      s.set(2, 2 + i, const XCell.empty(XStyle.expHeader2));
      s.merge(1, 2 + i, 2, 2 + i);
    }

    final days = e.days.isEmpty
        ? [ExpenseDay(date: DateTime(e.year, e.month, 1))]
        : e.days;
    var row = 3;
    for (final day in days) {
      s.set(
        row,
        1,
        XCell(style: XStyle.dayDate, number: excelSerial(day.date)),
      );
      s.set(row, 2, _text(day.name, XStyle.wrap));
      s.set(row, 3, _raw(day.amount, XStyle.int0));
      s.set(row, 4, _text(day.note, XStyle.numWrap));
      row++;
    }
    final last = row - 1;
    final totalRow = row;
    final prevRow = row + 1;
    final restRow = row + 2;
    final budgetRow = row + 3;

    s.set(totalRow, 1, _text('Итого', XStyle.headerBold));
    s.set(totalRow, 2, _text('-', XStyle.text));
    s.set(totalRow, 3, _formula('SUM(C3:C$last)', e.total, XStyle.int0));
    s.set(totalRow, 4, const XCell.empty(XStyle.text));

    s.set(prevRow, 1, _text('Остаток прошлого \nмесяца', XStyle.prevLabel));
    s.set(prevRow, 2, const XCell.empty(XStyle.prevMid));
    s.set(prevRow, 3, _raw(e.prevRemainder, XStyle.prevValue));
    s.set(prevRow, 4, const XCell.empty(XStyle.int0));
    s.rowHeights[prevRow] = 57;

    s.set(restRow, 1, _text('Остаток', XStyle.restLabel));
    s.set(restRow, 2, const XCell.empty(XStyle.restLabel));
    s.set(
      restRow,
      3,
      _formula('C$budgetRow-C$totalRow', e.remainder, XStyle.restValue),
    );
    s.set(restRow, 4, const XCell.empty(XStyle.int0));

    s.set(budgetRow, 1, _text('Бюджет', XStyle.budgetLabel));
    s.set(budgetRow, 2, const XCell.empty(XStyle.budgetMid));
    s.set(budgetRow, 3, _raw(e.budget, XStyle.budgetValue));
    s.set(budgetRow, 4, const XCell.empty(XStyle.int0));

    // «Обязательные расходы в мес.» — F1:H1 и список ниже.
    s.set(1, 6, _text(e.mandatoryTitle, XStyle.mandTitleL));
    s.set(1, 7, const XCell.empty(XStyle.mandTitleM));
    s.set(1, 8, const XCell.empty(XStyle.mandTitleR));
    s.merge(1, 6, 1, 8);
    final items = e.mandatory.isEmpty ? [MandatoryItem()] : e.mandatory;
    var mr = 2;
    for (var i = 0; i < items.length; i++) {
      final st = i == 0 ? XStyle.fillBlue : XStyle.text3;
      s.set(mr, 6, _text(items[i].name, st));
      s.set(mr, 7, _raw(items[i].plan, st));
      s.set(mr, 8, _raw(items[i].fact, st));
      mr++;
    }
    final mLast = mr - 1;
    s.set(mr, 6, _text('Сумма', XStyle.mandSumLabel));
    s.set(mr, 7, _formula('SUM(G2:G$mLast)', e.planTotal, XStyle.mandSum));
    s.set(mr, 8, _formula('SUM(H2:H$mLast)', e.factTotal, XStyle.mandSum));
  }

  static void _dynamics(XSheet s, DynamicsSheet dyn) {
    s.colWidths.addAll({1: 13.28515625, 2: 13.140625, 3: 11.28515625});
    for (var i = 2; i < dyn.years.length; i++) {
      s.colWidths[2 + i] = 13.140625;
    }
    s.set(1, 1, _text(dyn.header, XStyle.headerBold2));
    for (var y = 0; y < dyn.years.length; y++) {
      s.set(
        1,
        2 + y,
        XCell(style: XStyle.headerBold2, number: dyn.years[y].year.toDouble()),
      );
    }
    for (var m = 0; m < 12; m++) {
      s.set(
        m + 2,
        1,
        _text(kMonths[m], m == 0 ? XStyle.monthName : XStyle.text),
      );
      for (var y = 0; y < dyn.years.length; y++) {
        s.set(m + 2, 2 + y, _raw(dyn.years[y].values[m], XStyle.num2));
      }
    }
    s.set(14, 1, _text('Итого', XStyle.headerBold2));
    for (var y = 0; y < dyn.years.length; y++) {
      final col = XSheet.colName(2 + y);
      // Как в исходнике: у первого года формат «₽», у следующих — #,##0.00.
      s.set(
        14,
        2 + y,
        _formula(
          'IFERROR(AVERAGE(${col}2:${col}13),0)',
          dyn.years[y].average,
          y == 0 ? XStyle.rubInt : XStyle.num2,
        ),
      );
    }
  }

  static void _debts(XSheet s, BudgetData d) {
    s.colWidths.addAll({
      1: 16.140625,
      2: 11.28515625,
      3: 16.85546875,
      4: 13.5703125,
    });
    const heads = ['Дата', 'Сумма', 'Кому я должен', 'На что брал'];
    for (var i = 0; i < heads.length; i++) {
      s.set(1, 1 + i, _text(heads[i], XStyle.headerBold2));
    }
    final rows = d.debts.length < 3 ? 3 : d.debts.length;
    for (var i = 0; i < rows; i++) {
      final r = 2 + i;
      if (i >= d.debts.length) {
        for (var c = 1; c <= 4; c++) {
          s.set(r, c, const XCell.empty(XStyle.num2));
        }
        continue;
      }
      final debt = d.debts[i];
      final date = parseRuDate(debt.date);
      s.set(
        r,
        1,
        date != null
            ? XCell(style: XStyle.date, number: excelSerial(date))
            : _text(debt.date, XStyle.num2),
      );
      s.set(r, 2, _raw(debt.amount, XStyle.num2));
      s.set(r, 3, _text(debt.creditor, XStyle.num2));
      s.set(r, 4, _text(debt.purpose, XStyle.num2));
    }
    final last = 1 + rows;
    s.set(last + 2, 1, _text('Общий долг', XStyle.boldNum2));
    s.set(last + 2, 2, _formula('SUM(B2:B$last)', d.debtTotal, XStyle.num2));
  }

  // ───────────────────────────── Импорт ─────────────────────────────

  static ImportResult import(Uint8List bytes) {
    final book = XlsxReader.read(bytes);
    final warnings = <String>[];
    final tpl = BudgetData.template();

    // Баланс
    var months = <BalanceMonth>[];
    var shares = BudgetData.defaultShares();
    final bal = book.sheet('Баланс');
    if (bal == null) {
      warnings.add('Лист «Баланс» не найден — оставлены пустые данные.');
    } else {
      months = _readMonths(bal, book.date1904);
      shares = _readShares(bal) ?? shares;
      if (months.isEmpty) {
        warnings.add('На листе «Баланс» не найдено ни одного блока месяца.');
      }
    }

    // Расходы
    ExpenseSheet expenses;
    final exp = book.sheet('Расходы');
    if (exp == null) {
      warnings.add('Лист «Расходы» не найден — создан пустой месяц.');
      final now = DateTime.now();
      expenses = ExpenseSheet(
        monthTitle: monthTitle(now.year, now.month),
        year: now.year,
        month: now.month,
        days: ExpenseSheet.generateDays(now.year, now.month),
        mandatory: BudgetData.defaultMandatory(),
      );
    } else {
      expenses = _readExpenses(exp, book.date1904);
    }

    // Динамика
    DynamicsSheet dynamics;
    final dyn = book.sheet('Динамика');
    if (dyn == null) {
      warnings.add('Лист «Динамика» не найден.');
      dynamics = tpl.dynamics;
    } else {
      dynamics = _readDynamics(dyn);
    }

    // Долги
    var debts = <Debt>[];
    final dbt = book.sheet('Долги');
    if (dbt == null) {
      warnings.add('Лист «Долги» не найден.');
    } else {
      debts = _readDebts(dbt, book.date1904);
    }

    return ImportResult(
      BudgetData(
        months: months,
        shares: shares,
        expenses: expenses,
        dynamics: dynamics,
        debts: debts,
      ),
      warnings,
    );
  }

  static String _lower(RSheet s, int r, int c) => s.text(r, c).toLowerCase();

  /// Значение ячейки ввода. Арифметические формулы (`=50000`, `=1500+300`)
  /// сохраняются как формулы, формулы со ссылками — как вычисленное значение.
  static String rawOf(RCell? c) {
    if (c == null) return '';
    final f = c.formula?.trim() ?? '';
    if (f.isNotEmpty && Raw.isPureArithmetic(f)) return Raw.normalize('=$f');
    if (c.number != null) return Raw.formatNumber(c.number!);
    if (c.text != null) return c.text!.trim();
    return '';
  }

  static DateTime? _dateOf(RCell? c, bool date1904) {
    if (c == null) return null;
    if (c.number != null && c.number! > 0 && c.number! < 2958466) {
      return fromExcelSerial(c.number!, date1904: date1904);
    }
    if (c.text != null) return parseRuDate(c.text!);
    return null;
  }

  static DateTime? _dateFromTitle(String title) {
    final t = title.toLowerCase();
    for (var m = 0; m < 12; m++) {
      if (t.contains(kMonths[m].toLowerCase())) {
        final y = RegExp(r'(19|20)\d\d').firstMatch(t);
        return DateTime(
          y != null ? int.parse(y.group(0)!) : DateTime.now().year,
          m + 1,
          1,
        );
      }
    }
    return null;
  }

  static List<BalanceMonth> _readMonths(RSheet s, bool d1904) {
    final result = <BalanceMonth>[];
    final maxRow = s.maxRow;
    for (var h = 1; h <= maxRow; h++) {
      if (_lower(s, h, 1) != 'источник') continue;
      final title = h > 2 ? s.text(h - 2, 1) : '';
      final date =
          (h > 1 ? _dateOf(s.cell(h - 1, 1), d1904) : null) ??
          _dateFromTitle(title) ??
          DateTime.now();
      final sources = <BalanceSource>[];
      var r = h + 1;
      while (r <= maxRow) {
        final a = _lower(s, r, 1);
        if (a == 'итого' || a == 'источник') break;
        final any = [1, 2, 3, 4].any((c) => !(s.cell(r, c)?.isEmpty ?? true));
        if (any) {
          sources.add(
            BalanceSource(
              name: s.text(r, 1),
              currency: s.text(r, 2),
              balance: rawOf(s.cell(r, 3)),
              article: s.text(r, 4),
            ),
          );
        } else if (sources.isNotEmpty && r - h > 60) {
          break;
        }
        r++;
      }
      result.add(
        BalanceMonth(
          title: title.isEmpty ? BalanceMonth.defaultTitle(date) : title,
          date: DateTime(date.year, date.month, date.day),
          sources: sources,
        ),
      );
      h = r;
    }
    return result;
  }

  static List<ShareRow>? _readShares(RSheet s) {
    for (final rowEntry in s.rows.entries) {
      for (final cellEntry in rowEntry.value.entries) {
        if (cellEntry.key < 5) continue;
        if (cellEntry.value.asText.trim().toLowerCase() != 'статья') continue;
        final col = cellEntry.key;
        final rows = <ShareRow>[];
        for (var r = rowEntry.key + 1; r <= rowEntry.key + 50; r++) {
          final label = s.text(r, col);
          if (label.toLowerCase() == 'итого') break;
          if (label.isEmpty && (s.cell(r, col + 1)?.isEmpty ?? true)) {
            if (rows.isNotEmpty) break;
            continue;
          }
          rows.add(ShareRow(label: label, amount: rawOf(s.cell(r, col + 1))));
        }
        return rows.isEmpty ? null : rows;
      }
    }
    return null;
  }

  static ExpenseSheet _readExpenses(RSheet s, bool d1904) {
    final maxRow = s.maxRow;
    final days = <ExpenseDay>[];
    var r = 2;
    for (; r <= maxRow; r++) {
      if (_lower(s, r, 1) == 'итого') break;
      final date = _dateOf(s.cell(r, 1), d1904);
      if (date == null) continue;
      days.add(
        ExpenseDay(
          date: date,
          name: s.text(r, 2),
          amount: rawOf(s.cell(r, 3)),
          note: s.text(r, 4),
        ),
      );
    }

    var prev = '', budget = '';
    for (var k = r; k <= maxRow && k <= r + 20; k++) {
      final a = _lower(s, k, 1);
      if (a.startsWith('остаток прошлого')) prev = rawOf(s.cell(k, 3));
      if (a == 'бюджет') budget = rawOf(s.cell(k, 3));
    }

    final title = s.text(1, 1);
    int year, month;
    if (days.isNotEmpty) {
      year = days.first.date.year;
      month = days.first.date.month;
    } else {
      // «Октябрь 2026» или просто «Октябрь».
      final date = _dateFromTitle(title) ?? DateTime.now();
      year = date.year;
      month = date.month;
    }

    // Обязательные расходы: первый непустой заголовок справа в строке 1.
    var mandatoryTitle = 'Обязательные расходы в мес.';
    final mandatory = <MandatoryItem>[];
    final row1 = s.rows[1] ?? {};
    final titleCol =
        (row1.keys
                .where((c) => c >= 5 && row1[c]!.asText.trim().isNotEmpty)
                .toList()
              ..sort())
            .firstOrNull;
    if (titleCol != null) {
      mandatoryTitle = s.text(1, titleCol);
      var empty = 0;
      for (var k = 2; k <= maxRow; k++) {
        final name = s.text(k, titleCol);
        if (name.toLowerCase() == 'сумма') break;
        final plan = rawOf(s.cell(k, titleCol + 1));
        final fact = rawOf(s.cell(k, titleCol + 2));
        if (name.isEmpty && plan.isEmpty && fact.isEmpty) {
          if (++empty > 3) break;
          continue;
        }
        empty = 0;
        mandatory.add(MandatoryItem(name: name, plan: plan, fact: fact));
      }
    }

    return ExpenseSheet(
      monthTitle: title.isEmpty ? monthTitle(year, month) : title,
      year: year,
      month: month,
      days: days.isEmpty ? ExpenseSheet.generateDays(year, month) : days,
      prevRemainder: prev,
      budget: budget,
      mandatoryTitle: mandatoryTitle,
      mandatory: mandatory,
    );
  }

  static DynamicsSheet _readDynamics(RSheet s) {
    final years = <DynamicsYear>[];
    for (var c = 2; c <= 60; c++) {
      final cell = s.cell(1, c);
      if (cell == null || cell.isEmpty) break;
      final y =
          cell.number?.round() ??
          int.tryParse(cell.asText.replaceAll(RegExp(r'\D'), ''));
      if (y == null) break;
      final values = List<String>.filled(12, '');
      for (var m = 0; m < 12; m++) {
        // Ищем строку по названию месяца, иначе — по позиции.
        var row = m + 2;
        for (var r = 2; r <= 20; r++) {
          if (_lower(s, r, 1) == kMonths[m].toLowerCase()) {
            row = r;
            break;
          }
        }
        values[m] = rawOf(s.cell(row, c));
      }
      years.add(DynamicsYear(year: y, values: values));
    }
    final header = s.text(1, 1);
    return DynamicsSheet(
      header: header.isEmpty ? 'Месяц / год' : header,
      years: years,
    );
  }

  static List<Debt> _readDebts(RSheet s, bool d1904) {
    final debts = <Debt>[];
    for (var r = 2; r <= s.maxRow; r++) {
      if (_lower(s, r, 1).startsWith('общий долг')) break;
      final c1 = s.cell(r, 1);
      String date;
      if (c1?.number != null && c1!.number! > 20000 && c1.number! < 2958466) {
        date = formatRuDate(fromExcelSerial(c1.number!, date1904: d1904));
      } else {
        date = c1?.asText.trim() ?? '';
      }
      final debt = Debt(
        date: date,
        amount: rawOf(s.cell(r, 2)),
        creditor: s.text(r, 3),
        purpose: s.text(r, 4),
      );
      if (!debt.isEmpty) debts.add(debt);
    }
    return debts;
  }
}

class ImportResult {
  final BudgetData data;
  final List<String> warnings;
  ImportResult(this.data, this.warnings);
}

String formatRuDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

DateTime? parseRuDate(String input) {
  final s = input.trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})$').firstMatch(s);
  if (m != null) {
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    final mo = int.parse(m.group(2)!), d = int.parse(m.group(1)!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    return DateTime(y, mo, d);
  }
  final iso = DateTime.tryParse(s);
  return iso == null ? null : DateTime(iso.year, iso.month, iso.day);
}

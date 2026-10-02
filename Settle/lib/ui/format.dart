import 'package:intl/intl.dart';

import '../model/budget.dart';
import '../model/calc.dart';

final _money = NumberFormat('#,##0.00', 'ru');
final _int = NumberFormat('#,##0', 'ru');

/// 45 678,90 ₽
String fmtMoney(double v) => '${_money.format(v)} ₽';

/// 45 679 ₽
String fmtMoneyInt(double v) => '${_int.format(v)} ₽';

/// 46,67 %
String fmtPercent(double v) =>
    '${(v * 100).toStringAsFixed(2).replaceAll('.', ',')} %';

/// Подпись оси: 50 тыс, 1,2 млн.
String fmtAxis(double v) {
  final a = v.abs();
  String s;
  if (a >= 1e6) {
    s = '${_trim(v / 1e6)} млн';
  } else if (a >= 1e3) {
    s = '${_trim(v / 1e3)} тыс';
  } else {
    s = _int.format(v);
  }
  return s;
}

String _trim(double v) {
  final s = v.toStringAsFixed(v.abs() >= 10 ? 0 : 1);
  return s.endsWith('.0')
      ? s.substring(0, s.length - 2)
      : s.replaceAll('.', ',');
}

/// Ошибки Excel в том виде, как их показывает русский Excel.
String excelError(String code) => switch (code) {
  '#VALUE!' => '#ЗНАЧ!',
  '#NUM!' => '#ЧИСЛО!',
  _ => code,
};

String fmtCalcMoney(CalcValue? v) {
  if (v == null) return '';
  if (v.isError) return excelError(v.error!);
  return fmtMoney(v.number!);
}

String fmtCalcPercent(CalcValue? v) {
  if (v == null) return '';
  if (v.isError) return excelError(v.error!);
  return fmtPercent(v.number!);
}

/// Отображение «сырого» значения ячейки как денег.
String fmtRawMoney(String raw) {
  final v = Raw.eval(raw);
  if (v == null) return raw;
  return fmtCalcMoney(v);
}

/// 1 800 ₽, но 1 800,50 ₽ — копейки показываются, только если они есть.
String fmtMoneyShort(double v) =>
    v == v.truncateToDouble() ? fmtMoneyInt(v) : fmtMoney(v);

String fmtCalcMoneyShort(CalcValue? v) {
  if (v == null) return '';
  if (v.isError) return excelError(v.error!);
  return fmtMoneyShort(v.number!);
}

/// Отображение «сырого» значения в коротком денежном формате (лист «Расходы»).
String fmtRawMoneyShort(String raw) {
  final v = Raw.eval(raw);
  if (v == null) return raw;
  return fmtCalcMoneyShort(v);
}

String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// 1 октября
String fmtDayMonth(DateTime d) => '${d.day} ${kMonthsGenitive[d.month - 1]}';

const _weekdays = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
String weekday(DateTime d) => _weekdays[d.weekday - 1];

String monthYear(int year, int month) => monthTitle(year, month);

String initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '•';
  if (parts.length == 1) return parts.first.characters2.toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

extension on String {
  String get characters2 => length <= 2 ? this : substring(0, 2);
}

/// 1 день, 2 дня, 5 дней.
String plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

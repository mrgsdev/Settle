import 'dart:math' as math;

/// Результат вычисления «как в Excel»: число либо ошибка (`#VALUE!`, `#NUM!`).
/// В отличие от Excel деление на ноль даёт 0, а не `#DIV/0!`.
class CalcValue {
  final double? number;
  final String? error;

  const CalcValue.num(double this.number) : error = null;
  const CalcValue.err(String this.error) : number = null;

  static const zero = CalcValue.num(0);
  static const value = CalcValue.err('#VALUE!');

  bool get isError => error != null;

  CalcValue operator +(CalcValue o) =>
      isError ? this : (o.isError ? o : CalcValue.num(number! + o.number!));

  CalcValue operator -(CalcValue o) =>
      isError ? this : (o.isError ? o : CalcValue.num(number! - o.number!));

  CalcValue operator /(CalcValue o) {
    if (isError) return this;
    if (o.isError) return o;
    if (o.number == 0) return zero;
    return CalcValue.num(number! / o.number!);
  }

  @override
  String toString() => error ?? '$number';
}

/// Работа с «сырыми» значениями ячеек.
///
/// Каждая числовая ячейка хранится строкой ровно так, как её ввёл пользователь:
/// `""` — пусто, `"1500"` — число, `"=1500+300"` — формула (как `=50000` в
/// ячейке «Бюджет» исходного файла). Формулы из арифметики сохраняются и
/// попадают в Excel как настоящие формулы.
class Raw {
  Raw._();

  static bool isFormula(String raw) => raw.trimLeft().startsWith('=');

  /// Формула без ссылок на ячейки, которую приложение умеет вычислить само.
  static final _arith = RegExp(r'^[0-9\s.,+\-*/()%^]+$');
  static bool isPureArithmetic(String formula) => _arith.hasMatch(formula);

  /// Значение для функций SUM/AVERAGE: `null` — пусто или текст (Excel их
  /// пропускает), иначе число или ошибка.
  static CalcValue? eval(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('=')) {
      final r = _Expr(s.substring(1)).parse();
      return r;
    }
    final n = parseNumber(s);
    return n == null ? null : CalcValue.num(n);
  }

  /// Значение при прямой ссылке на ячейку (`=I3/I6`): пусто → 0, текст → #VALUE!.
  static CalcValue ref(String raw) {
    if (raw.trim().isEmpty) return CalcValue.zero;
    return eval(raw) ?? CalcValue.value;
  }

  /// Число для графиков и сводок: ошибки и текст считаются нулём.
  static double num(String raw) => eval(raw)?.number ?? 0;

  /// Сумма по правилам SUM: текст и пустые ячейки пропускаются, ошибка «заражает».
  static CalcValue sum(Iterable<String> raws) {
    var total = 0.0;
    for (final r in raws) {
      final v = eval(r);
      if (v == null) continue;
      if (v.isError) return v;
      total += v.number!;
    }
    return CalcValue.num(total);
  }

  /// Среднее по правилам AVERAGE, но без чисел — 0 (в Excel было бы #DIV/0!).
  static CalcValue average(Iterable<String> raws) {
    var total = 0.0;
    var count = 0;
    for (final r in raws) {
      final v = eval(r);
      if (v == null) continue;
      if (v.isError) return v;
      total += v.number!;
      count++;
    }
    return count == 0 ? CalcValue.zero : CalcValue.num(total / count);
  }

  /// Разбор числа в русском или английском написании: `1 234,5`, `1234.5`, `-20`.
  static double? parseNumber(String input) {
    var s = input.trim().replaceAll(RegExp(r'[\s  ₽]'), '');
    if (s.isEmpty) return null;
    if (s.contains(',') && s.contains('.')) {
      // 1,234.56 → 1234.56
      s = s.replaceAll(',', '');
    } else {
      s = s.replaceAll(',', '.');
    }
    return double.tryParse(s);
  }

  /// Каноническая строка числа: без хвостового `.0`.
  static String formatNumber(double n) {
    if (n == n.truncateToDouble() && n.abs() < 1e15) {
      return n.toInt().toString();
    }
    return n.toString();
  }

  /// Приведение пользовательского ввода к хранимому виду.
  static String normalize(String input) {
    final s = input.trim();
    if (s.isEmpty) return '';
    if (s.startsWith('=')) {
      final body = s.substring(1).replaceAll(RegExp(r'[\s ]'), '');
      if (body.isEmpty) return '';
      // В формулах Excel десятичный разделитель — точка.
      return '=${body.replaceAll(',', '.')}';
    }
    final n = parseNumber(s);
    if (n != null) return formatNumber(n);
    // «50+40» без «=» — тоже формула.
    final body = s.replaceAll(RegExp(r'[\s ]'), '');
    if (isPureArithmetic(body)) return '=${body.replaceAll(',', '.')}';
    return s;
  }
}

/// Мини-вычислитель арифметики: + - * / ^ %, скобки, унарный минус.
class _Expr {
  _Expr(String src)
    : s = src.replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.');

  final String s;
  int i = 0;

  CalcValue? parse() {
    if (s.isEmpty) return null;
    try {
      final v = _expr();
      if (i != s.length) return CalcValue.value;
      return v;
    } on FormatException {
      return CalcValue.value;
    }
  }

  CalcValue _expr() {
    var v = _term();
    while (i < s.length && (s[i] == '+' || s[i] == '-')) {
      final op = s[i++];
      final r = _term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  CalcValue _term() {
    var v = _power();
    while (i < s.length && (s[i] == '*' || s[i] == '/')) {
      final op = s[i++];
      final r = _power();
      if (op == '*') {
        v = v.isError
            ? v
            : (r.isError ? r : CalcValue.num(v.number! * r.number!));
      } else {
        v = v / r;
      }
    }
    return v;
  }

  CalcValue _power() {
    final base = _unary();
    if (i < s.length && s[i] == '^') {
      i++;
      final exp = _power();
      if (base.isError) return base;
      if (exp.isError) return exp;
      final r = math.pow(base.number!, exp.number!).toDouble();
      return r.isFinite ? CalcValue.num(r) : CalcValue.err('#NUM!');
    }
    return base;
  }

  CalcValue _unary() {
    if (i < s.length && (s[i] == '-' || s[i] == '+')) {
      final neg = s[i++] == '-';
      final v = _unary();
      return neg && !v.isError ? CalcValue.num(-v.number!) : v;
    }
    return _percent();
  }

  CalcValue _percent() {
    var v = _atom();
    while (i < s.length && s[i] == '%') {
      i++;
      if (!v.isError) v = CalcValue.num(v.number! / 100);
    }
    return v;
  }

  CalcValue _atom() {
    if (i >= s.length) throw const FormatException();
    if (s[i] == '(') {
      i++;
      final v = _expr();
      if (i >= s.length || s[i] != ')') throw const FormatException();
      i++;
      return v;
    }
    final start = i;
    while (i < s.length && (RegExp(r'[0-9.]').hasMatch(s[i]))) {
      i++;
    }
    if (start == i) throw const FormatException();
    final n = double.tryParse(s.substring(start, i));
    if (n == null) throw const FormatException();
    return CalcValue.num(n);
  }
}

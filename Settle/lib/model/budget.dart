import 'calc.dart';

/// Модель повторяет структуру файла «Бюджет.xlsx» лист в лист:
/// Баланс · Расходы · Динамика · Долги.

const kMonths = [
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
];
const kMonthsShort = [
  'Янв',
  'Фев',
  'Мар',
  'Апр',
  'Май',
  'Июн',
  'Июл',
  'Авг',
  'Сен',
  'Окт',
  'Ноя',
  'Дек',
];
const kMonthsGenitive = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

const kMonthsDative = [
  'январю',
  'февралю',
  'марту',
  'апрелю',
  'маю',
  'июню',
  'июлю',
  'августу',
  'сентябрю',
  'октябрю',
  'ноябрю',
  'декабрю',
];

const kArticles = ['Потребление', 'Инвестиции', 'Сбережение'];
const kCurrencies = ['Рубли', 'Доллары', 'Евро', 'Криптовалюты'];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// «Октябрь 2026» — название месяца по умолчанию (его можно переименовать).
String monthTitle(int year, int month) => '${kMonths[month - 1]} $year';

// ───────────────────────────── Баланс ─────────────────────────────

class BalanceSource {
  String name;
  String currency;
  String balance; // raw
  String article;

  BalanceSource({
    this.name = '',
    this.currency = 'Рубли',
    this.balance = '',
    this.article = 'Потребление',
  });

  BalanceSource copyEmpty() =>
      BalanceSource(name: name, currency: currency, article: article);

  Map<String, dynamic> toJson() => {
    'name': name,
    'currency': currency,
    'balance': balance,
    'article': article,
  };
  factory BalanceSource.fromJson(Map<String, dynamic> j) => BalanceSource(
    name: j['name'] ?? '',
    currency: j['currency'] ?? '',
    balance: j['balance'] ?? '',
    article: j['article'] ?? '',
  );
}

/// Блок месяца на листе «Баланс»: заголовок, дата, источники, Итого/Сальдо/Изменение.
class BalanceMonth {
  String title;
  DateTime date;
  List<BalanceSource> sources;

  BalanceMonth({
    required this.title,
    required this.date,
    required this.sources,
  });

  static String defaultTitle(DateTime d) => monthTitle(d.year, d.month);

  /// =SUM(C…:C…)
  CalcValue get total => Raw.sum(sources.map((s) => s.balance));

  Map<String, dynamic> toJson() => {
    'title': title,
    'date': date.toIso8601String(),
    'sources': sources.map((s) => s.toJson()).toList(),
  };
  factory BalanceMonth.fromJson(Map<String, dynamic> j) => BalanceMonth(
    title: j['title'] ?? '',
    date: DateTime.tryParse(j['date'] ?? '') ?? DateTime.now(),
    sources: [
      for (final s in (j['sources'] as List? ?? [])) BalanceSource.fromJson(s),
    ],
  );
}

/// Таблица «Статья · Сумма · Доля» справа на листе «Баланс» (H2:J6).
class ShareRow {
  String label;
  String amount; // raw
  ShareRow({required this.label, this.amount = ''});

  Map<String, dynamic> toJson() => {'label': label, 'amount': amount};
  factory ShareRow.fromJson(Map<String, dynamic> j) =>
      ShareRow(label: j['label'] ?? '', amount: j['amount'] ?? '');
}

// ───────────────────────────── Расходы ─────────────────────────────

class ExpenseDay {
  DateTime date;
  String name;
  String amount; // raw
  String note;
  ExpenseDay({
    required this.date,
    this.name = '',
    this.amount = '',
    this.note = '',
  });

  bool get isEmpty =>
      name.trim().isEmpty && amount.trim().isEmpty && note.trim().isEmpty;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'name': name,
    'amount': amount,
    'note': note,
  };
  factory ExpenseDay.fromJson(Map<String, dynamic> j) => ExpenseDay(
    date: DateTime.tryParse(j['date'] ?? '') ?? DateTime.now(),
    name: j['name'] ?? '',
    amount: j['amount'] ?? '',
    note: j['note'] ?? '',
  );
}

/// «Обязательные расходы в мес.» (F1:H8). Колонки G и H в файле без заголовков,
/// в приложении они подписаны «План» и «Факт».
class MandatoryItem {
  String name;
  String plan; // raw, колонка G
  String fact; // raw, колонка H
  MandatoryItem({this.name = '', this.plan = '', this.fact = ''});

  Map<String, dynamic> toJson() => {'name': name, 'plan': plan, 'fact': fact};
  factory MandatoryItem.fromJson(Map<String, dynamic> j) => MandatoryItem(
    name: j['name'] ?? '',
    plan: j['plan'] ?? '',
    fact: j['fact'] ?? '',
  );
}

class ExpenseSheet {
  String monthTitle; // A1, «Октябрь 2026»
  int year;
  int month;
  List<ExpenseDay> days;
  String prevRemainder; // «Остаток прошлого месяца», raw
  String budget; // «Бюджет», raw (в исходнике — формула =50000)
  String mandatoryTitle;
  List<MandatoryItem> mandatory;

  ExpenseSheet({
    required this.monthTitle,
    required this.year,
    required this.month,
    required this.days,
    this.prevRemainder = '',
    this.budget = '',
    this.mandatoryTitle = 'Обязательные расходы в мес.',
    required this.mandatory,
  });

  static List<ExpenseDay> generateDays(int year, int month) => [
    for (var d = 1; d <= daysInMonth(year, month); d++)
      ExpenseDay(date: DateTime(year, month, d)),
  ];

  /// Итого: =SUM(C3:C<последний день>)
  CalcValue get total => Raw.sum(days.map((d) => d.amount));

  /// Остаток: =Бюджет − Итого (как в исходном файле, без остатка прошлого месяца).
  CalcValue get remainder => Raw.ref(budget) - total;

  /// Суммы по дням месяца (индекс 0 — первое число), для графиков.
  List<double> get dailyTotals {
    final list = List<double>.filled(daysInMonth(year, month), 0);
    for (final d in days) {
      if (d.date.year == year && d.date.month == month) {
        list[d.date.day - 1] += Raw.num(d.amount);
      }
    }
    return list;
  }

  CalcValue get planTotal => Raw.sum(mandatory.map((m) => m.plan));
  CalcValue get factTotal => Raw.sum(mandatory.map((m) => m.fact));

  Map<String, dynamic> toJson() => {
    'monthTitle': monthTitle,
    'year': year,
    'month': month,
    'days': days.map((d) => d.toJson()).toList(),
    'prevRemainder': prevRemainder,
    'budget': budget,
    'mandatoryTitle': mandatoryTitle,
    'mandatory': mandatory.map((m) => m.toJson()).toList(),
  };
  factory ExpenseSheet.fromJson(Map<String, dynamic> j) => ExpenseSheet(
    monthTitle: j['monthTitle'] ?? '',
    year: j['year'] ?? DateTime.now().year,
    month: j['month'] ?? DateTime.now().month,
    days: [for (final d in (j['days'] as List? ?? [])) ExpenseDay.fromJson(d)],
    prevRemainder: j['prevRemainder'] ?? '',
    budget: j['budget'] ?? '',
    mandatoryTitle: j['mandatoryTitle'] ?? 'Обязательные расходы в мес.',
    mandatory: [
      for (final m in (j['mandatory'] as List? ?? []))
        MandatoryItem.fromJson(m),
    ],
  );
}

// ───────────────────────────── Динамика ─────────────────────────────

class DynamicsYear {
  int year;
  List<String> values; // 12 raw значений, январь…декабрь
  DynamicsYear({required this.year, List<String>? values})
    : values = values ?? List.filled(12, '', growable: false);

  /// «Итого» в файле считается как =AVERAGE(B2:B13)
  CalcValue get average => Raw.average(values);

  Map<String, dynamic> toJson() => {'year': year, 'values': values};
  factory DynamicsYear.fromJson(Map<String, dynamic> j) {
    final v = [for (final x in (j['values'] as List? ?? [])) '$x'];
    while (v.length < 12) {
      v.add('');
    }
    return DynamicsYear(
      year: j['year'] ?? DateTime.now().year,
      values: v.take(12).toList(),
    );
  }
}

class DynamicsSheet {
  String header; // «Месяц / год»
  List<DynamicsYear> years;
  DynamicsSheet({this.header = 'Месяц / год', required this.years});

  Map<String, dynamic> toJson() => {
    'header': header,
    'years': years.map((y) => y.toJson()).toList(),
  };
  factory DynamicsSheet.fromJson(Map<String, dynamic> j) => DynamicsSheet(
    header: j['header'] ?? 'Месяц / год',
    years: [
      for (final y in (j['years'] as List? ?? [])) DynamicsYear.fromJson(y),
    ],
  );
}

// ───────────────────────────── Долги ─────────────────────────────

class Debt {
  String date; // «дд.мм.гггг» или произвольный текст
  String amount; // raw
  String creditor;
  String purpose;
  Debt({
    this.date = '',
    this.amount = '',
    this.creditor = '',
    this.purpose = '',
  });

  bool get isEmpty =>
      date.isEmpty && amount.isEmpty && creditor.isEmpty && purpose.isEmpty;

  Map<String, dynamic> toJson() => {
    'date': date,
    'amount': amount,
    'creditor': creditor,
    'purpose': purpose,
  };
  factory Debt.fromJson(Map<String, dynamic> j) => Debt(
    date: j['date'] ?? '',
    amount: j['amount'] ?? '',
    creditor: j['creditor'] ?? '',
    purpose: j['purpose'] ?? '',
  );
}

// ───────────────────────────── Книга целиком ─────────────────────────────

class BudgetData {
  List<BalanceMonth> months;
  List<ShareRow> shares;
  ExpenseSheet expenses;
  DynamicsSheet dynamics;
  List<Debt> debts;

  BudgetData({
    required this.months,
    required this.shares,
    required this.expenses,
    required this.dynamics,
    required this.debts,
  });

  /// Сальдо блока i: =Итого(i) − Итого(i−1). Для первого блока пусто.
  CalcValue? saldo(int i) =>
      i <= 0 ? null : months[i].total - months[i - 1].total;

  /// «Изменение в %» блока i, как в файле: =(Итого(i) − Итого(i−1)) / Итого(i);
  /// при нулевом итоге — 0.
  CalcValue? change(int i) =>
      i <= 0 ? null : (months[i].total - months[i - 1].total) / months[i].total;

  CalcValue get sharesTotal => Raw.sum(shares.map((s) => s.amount));

  /// Доля: =I3/I6
  CalcValue shareOf(int i) => Raw.ref(shares[i].amount) / sharesTotal;

  /// Итог доли: =SUM(J3:J5) — ошибки в строках «заражают» итог.
  CalcValue get sharesShareTotal {
    var total = CalcValue.zero;
    for (var i = 0; i < shares.length; i++) {
      total = total + shareOf(i);
    }
    return total;
  }

  /// Общий долг: =SUM(B…)
  CalcValue get debtTotal => Raw.sum(debts.map((d) => d.amount));

  Map<String, dynamic> toJson() => {
    'version': 1,
    'months': months.map((m) => m.toJson()).toList(),
    'shares': shares.map((s) => s.toJson()).toList(),
    'expenses': expenses.toJson(),
    'dynamics': dynamics.toJson(),
    'debts': debts.map((d) => d.toJson()).toList(),
  };

  factory BudgetData.fromJson(Map<String, dynamic> j) => BudgetData(
    months: [
      for (final m in (j['months'] as List? ?? [])) BalanceMonth.fromJson(m),
    ],
    shares: [
      for (final s in (j['shares'] as List? ?? [])) ShareRow.fromJson(s),
    ],
    expenses: ExpenseSheet.fromJson(j['expenses'] ?? {}),
    dynamics: DynamicsSheet.fromJson(j['dynamics'] ?? {}),
    debts: [for (final d in (j['debts'] as List? ?? [])) Debt.fromJson(d)],
  );

  BudgetData clone() => BudgetData.fromJson(toJson());

  static List<ShareRow> defaultShares() => [
    ShareRow(label: 'Потребление'),
    ShareRow(label: 'Инвестиции'),
    ShareRow(label: 'Сбережения'),
  ];

  static List<MandatoryItem> defaultMandatory() => [
    MandatoryItem(name: 'ЖКХ'),
    MandatoryItem(name: 'Еда (месяц)'),
    MandatoryItem(name: 'Транспорт'),
    MandatoryItem(name: 'Мобильная связь'),
    MandatoryItem(name: 'Интернет'),
    MandatoryItem(name: 'Прочие расходы (разное)'),
  ];

  /// Стартовые данные: текущий месяц, все суммы и счета пустые.
  factory BudgetData.template([DateTime? today]) {
    final now = today ?? DateTime.now();
    final month = DateTime(now.year, now.month, 1);
    return BudgetData(
      months: [
        BalanceMonth(
          title: BalanceMonth.defaultTitle(month),
          date: month,
          sources: [BalanceSource()],
        ),
      ],
      shares: defaultShares(),
      expenses: ExpenseSheet(
        monthTitle: monthTitle(now.year, now.month),
        year: now.year,
        month: now.month,
        days: ExpenseSheet.generateDays(now.year, now.month),
        mandatory: defaultMandatory(),
      ),
      dynamics: DynamicsSheet(years: [DynamicsYear(year: now.year)]),
      debts: [],
    );
  }
}

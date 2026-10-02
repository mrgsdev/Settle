import 'package:settle/model/budget.dart';

/// Правдоподобные данные для скриншотов и UI-тестов.
BudgetData demoData() {
  final d = BudgetData.template(DateTime(2026, 9, 15));
  List<BalanceSource> src(List<String> v) => [
    BalanceSource(
      name: 'Visa',
      currency: 'Рубли',
      balance: v[0],
      article: 'Потребление',
    ),
    BalanceSource(
      name: 'Карта Тинькофф',
      currency: 'Рубли',
      balance: v[1],
      article: 'Потребление',
    ),
    BalanceSource(
      name: 'Наличные',
      currency: 'Рубли',
      balance: v[2],
      article: 'Инвестиции',
    ),
    BalanceSource(
      name: 'Кошелек',
      currency: 'Евро',
      balance: v[3],
      article: 'Сбережение',
    ),
    BalanceSource(
      name: 'Крипта',
      currency: 'Криптовалюты',
      balance: v[4],
      article: 'Потребление',
    ),
  ];
  d.months = [
    BalanceMonth(
      title: 'Июль 2026',
      date: DateTime(2026, 7, 1),
      sources: src(['38200', '61450', '15000', '42000', '9800']),
    ),
    BalanceMonth(
      title: 'Август 2026',
      date: DateTime(2026, 8, 1),
      sources: src(['41250', '58900', '20000', '45500', '12400']),
    ),
    BalanceMonth(
      title: 'Сентябрь 2026',
      date: DateTime(2026, 9, 1),
      sources: src(['45678.9', '72310', '20000', '48000', '10150']),
    ),
  ];
  d.shares = [
    ShareRow(label: 'Потребление', amount: '128138.9'),
    ShareRow(label: 'Инвестиции', amount: '20000'),
    ShareRow(label: 'Сбережения', amount: '48000'),
  ];
  final e = ExpenseSheet(
    monthTitle: 'Сентябрь 2026',
    year: 2026,
    month: 9,
    days: ExpenseSheet.generateDays(2026, 9),
    budget: '=50000',
    prevRemainder: '3250',
    mandatory: BudgetData.defaultMandatory(),
  );
  final spend = <int, (String, String, String)>{
    1: ('Транспорт + ЖКХ', '=6500+1200', ''),
    2: ('Продукты', '2350', 'Перекрёсток'),
    4: ('Кофе', '320', ''),
    5: ('Продукты', '=1890+640', ''),
    7: ('Аптека', '1180', ''),
    9: ('Мобильная связь', '650', ''),
    10: ('Интернет', '700', ''),
    12: ('Продукты', '3120', 'на неделю'),
    14: ('Кино', '1400', 'с друзьями'),
    16: ('Одежда', '4990', 'куртка'),
    18: ('Продукты', '2780', ''),
    20: ('Такси', '890', ''),
    21: ('Подарок', '3500', 'маме'),
    23: ('Продукты', '2460', ''),
    25: ('Кафе', '1850', ''),
    27: ('Продукты', '2990', ''),
    29: ('Книги', '1290', ''),
  };
  for (final entry in spend.entries) {
    final day = e.days[entry.key - 1];
    day.name = entry.value.$1;
    day.amount = entry.value.$2;
    day.note = entry.value.$3;
  }
  final plans = ['7700', '15000', '3000', '650', '700', '5000'];
  final facts = ['7700', '15590', '2890', '650', '700', '6210'];
  for (var i = 0; i < e.mandatory.length; i++) {
    e.mandatory[i].plan = plans[i];
    e.mandatory[i].fact = facts[i];
  }
  d.expenses = e;
  d.dynamics = DynamicsSheet(
    years: [DynamicsYear(year: 2025), DynamicsYear(year: 2026)],
  );
  d.dynamics.years[0].values.setAll(0, [
    '41200',
    '38900',
    '44100',
    '39800',
    '47250',
    '52300',
    '58900',
    '49600',
    '43700',
    '45100',
    '46800',
    '61200',
  ]);
  d.dynamics.years[1].values.setAll(0, [
    '44300',
    '40150',
    '42800',
    '45900',
    '48700',
    '50100',
    '55400',
    '51200',
    '',
    '',
    '',
    '',
  ]);
  d.debts = [
    Debt(
      date: '12.08.2026',
      amount: '15000',
      creditor: 'Иван',
      purpose: 'Ремонт машины',
    ),
    Debt(
      date: '03.09.2026',
      amount: '4500',
      creditor: 'Аня',
      purpose: 'Билеты в театр',
    ),
    Debt(
      date: '20.09.2026',
      amount: '=2000*3',
      creditor: 'Иван',
      purpose: 'До зарплаты',
    ),
  ];
  return d;
}

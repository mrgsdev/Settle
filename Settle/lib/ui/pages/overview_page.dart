import 'package:flutter/material.dart';

import '../../model/budget.dart';
import '../../model/calc.dart';
import '../../model/store.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

/// Дашборд: показатели, траты месяца, счета, крупные траты и динамика.
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  int? _month;
  int? _year;

  @override
  Widget build(BuildContext context) {
    final d = StoreScope.of(context).data;
    final e = d.expenses;
    final mi = d.months.isEmpty
        ? -1
        : (_month ?? d.months.length - 1).clamp(0, d.months.length - 1);
    final month = mi >= 0 ? d.months[mi] : null;
    final daily = e.dailyTotals;
    final budget = Raw.eval(e.budget)?.number;

    final years = d.dynamics.years;
    final yi = years.isEmpty ? -1 : years.indexWhere((y) => y.year == _year);
    final year = years.isEmpty
        ? null
        : (yi >= 0 ? years[yi] : _defaultYear(years, e.year));

    return PageBody(
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: d.months.length > 1
                    ? StepPicker<int>(
                        items: [
                          for (var i = 0; i < d.months.length; i++)
                            (
                              i,
                              monthYear(
                                d.months[i].date.year,
                                d.months[i].date.month,
                              ),
                            ),
                        ],
                        value: mi,
                        onChanged: (i) => setState(() => _month = i),
                      )
                    : const SizedBox(height: 40),
              ),
            ),
            Text(
              'Сегодня ${fmtDayMonth(DateTime.now())} ${DateTime.now().year}',
              style: AppText.muted,
            ),
          ],
        ),
        const SizedBox(height: 32),
        KpiGrid(
          children: [
            _balanceKpi(d, mi, month),
            KpiCard(
              title: 'Расходы · ${kMonths[e.month - 1]}',
              value: fmtCalcMoneyShort(e.total),
              subtitle: budget != null && budget > 0
                  ? 'из бюджета ${fmtMoneyInt(budget)}'
                  : 'Бюджет не задан',
            ),
            _restKpi(e, budget),
            KpiCard(
              title: 'Общий долг',
              value: fmtCalcMoney(d.debtTotal),
              subtitle: d.debts.isEmpty
                  ? 'Долгов нет'
                  : '${d.debts.length} ${plural(d.debts.length, 'запись', 'записи', 'записей')}',
            ),
          ],
        ),
        const SizedBox(height: 32),
        ResponsiveRow(
          flex: const [7, 5],
          children: [
            AppCard(
              title: 'Расходы за месяц',
              trailing: Text(monthYear(e.year, e.month), style: AppText.muted),
              height: 420,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CumulativeSpendChart(
                      sheet: e,
                      daily: daily,
                      budget: budget,
                    ),
                  ),
                  if (daily.every((v) => v == 0))
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          'Пока нет трат — добавьте их на вкладке «Расходы»',
                          style: AppText.small,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            AppCard(
              title: month == null
                  ? 'Счета'
                  : 'Счета · ${kMonths[month.date.month - 1]}',
              trailing: AppButton.ghost(
                label: 'Открыть',
                onPressed: () => widget.onNavigate(1),
              ),
              height: 420,
              child: month == null || month.sources.isEmpty
                  ? const Center(
                      child: EmptyState(
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'Нет счетов',
                        text: 'Добавьте источники на вкладке «Баланс»',
                      ),
                    )
                  : _Accounts(month: month),
            ),
          ],
        ),
        const SizedBox(height: 32),
        ResponsiveRow(
          flex: const [5, 7],
          children: [
            AppCard(
              title: 'Крупные траты',
              trailing: Text(monthYear(e.year, e.month), style: AppText.muted),
              height: 460,
              child: _TopExpenses(sheet: e),
            ),
            AppCard(
              title: 'Динамика',
              trailing: years.length > 1
                  ? StepPicker<int>(
                      items: [for (final y in years) (y.year, '${y.year}')],
                      value: year!.year,
                      onChanged: (v) => setState(() => _year = v),
                    )
                  : (year != null
                        ? Text('${year.year}', style: AppText.muted)
                        : null),
              height: 460,
              child: year == null
                  ? const Center(
                      child: EmptyState(
                        icon: Icons.bar_chart_rounded,
                        title: 'Нет данных',
                        text: 'Добавьте год на вкладке «Динамика»',
                      ),
                    )
                  : MonthBarsChart(
                      year: year.year,
                      values: [
                        for (final v in year.values) Raw.eval(v)?.number,
                      ],
                    ),
            ),
          ],
        ),
      ],
    );
  }

  DynamicsYear _defaultYear(List<DynamicsYear> years, int expensesYear) {
    final match = years.where((y) => y.year == expensesYear).firstOrNull;
    return match ?? years.last;
  }

  Widget _balanceKpi(BudgetData d, int mi, BalanceMonth? month) {
    if (month == null) {
      return const KpiCard(
        title: 'Баланс',
        value: '—',
        subtitle: 'Добавьте месяц на вкладке «Баланс»',
      );
    }
    final saldo = d.saldo(mi);
    final change = d.change(mi);
    String subtitle;
    Color? color;
    if (saldo == null) {
      subtitle = 'Первый месяц в таблице';
    } else if (saldo.isError) {
      subtitle = excelError(saldo.error!);
    } else {
      // Как в карточках референса: «+20% month over month».
      subtitle = change == null || change.isError
          ? '${signed(fmtMoney(saldo.number!), saldo.number!)} к прошлому месяцу'
          : '${signed(fmtPercent(change.number!), change.number!)} к прошлому месяцу';
      color = signColor(saldo.number);
    }
    final card = KpiCard(
      title: 'Баланс · ${kMonths[month.date.month - 1]}',
      value: fmtCalcMoney(month.total),
      subtitle: subtitle,
      subtitleColor: color,
    );
    if (saldo == null || saldo.isError) return card;
    return Tooltip(
      message: 'Сальдо: ${signed(fmtMoney(saldo.number!), saldo.number!)}',
      child: card,
    );
  }

  Widget _restKpi(ExpenseSheet e, double? budget) {
    final rest = e.remainder;
    final used = budget != null && budget > 0 && !e.total.isError
        ? e.total.number! / budget
        : null;
    return KpiCard(
      title: 'Остаток бюджета',
      value: fmtCalcMoneyShort(rest),
      subtitle: used == null
          ? 'Бюджет − Итого'
          : 'Израсходовано ${fmtPercent(used)}',
      subtitleColor: (rest.number ?? 0) < 0 ? AppColors.negative : null,
      badge: used == null ? null : _UsageRing(value: used),
    );
  }
}

class _UsageRing extends StatelessWidget {
  const _UsageRing({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        value: value.clamp(0, 1),
        strokeWidth: 2.5,
        backgroundColor: AppColors.subtle,
        color: value > 1 ? AppColors.negative : AppColors.text,
      ),
    );
  }
}

class _Accounts extends StatelessWidget {
  const _Accounts({required this.month});
  final BalanceMonth month;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: month.sources.length,
      separatorBuilder: (_, _) => const SizedBox(height: 20),
      itemBuilder: (context, i) {
        final s = month.sources[i];
        final v = Raw.eval(s.balance);
        return Row(
          children: [
            Avatar(s.name.isEmpty ? '?' : s.name, size: 46),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name.isEmpty ? 'Без названия' : s.name,
                    style: AppText.body,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      s.currency,
                      s.article,
                    ].where((x) => x.isNotEmpty).join(' · '),
                    style: AppText.muted,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              v == null ? '—' : fmtCalcMoney(v),
              style: AppText.num.copyWith(
                color: v == null ? AppColors.faint : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TopExpenses extends StatelessWidget {
  const _TopExpenses({required this.sheet});
  final ExpenseSheet sheet;

  static const _cols = [
    Col(5),
    Col(4),
    Col(4, align: Alignment.centerRight),
    Col(0, width: 72, align: Alignment.centerRight),
  ];

  @override
  Widget build(BuildContext context) {
    final items = sheet.days.where((d) => Raw.num(d.amount) > 0).toList()
      ..sort((a, b) => Raw.num(b.amount).compareTo(Raw.num(a.amount)));
    final total = sheet.total.number ?? 0;
    if (items.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Трат пока нет',
          text: 'Они появятся здесь, когда вы заполните лист «Расходы»',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GridHeader(
          cols: _cols,
          labels: ['Наименование', 'Дата', 'Сумма', 'Доля'],
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final d in items.take(12))
                GridRow(
                  cols: _cols,
                  cells: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        d.name.isEmpty ? 'Без названия' : d.name,
                        style: AppText.body,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        fmtDayMonth(d.date),
                        style: AppText.muted,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        fmtMoneyShort(Raw.num(d.amount)),
                        style: AppText.num,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        total > 0
                            ? '${(Raw.num(d.amount) / total * 100).toStringAsFixed(1).replaceAll('.', ',')} %'
                            : '—',
                        style: AppText.num,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

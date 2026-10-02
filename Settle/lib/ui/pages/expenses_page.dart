import 'package:flutter/material.dart';

import '../../model/budget.dart';
import '../../model/calc.dart';
import '../../model/store.dart';
import '../actions.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/cells.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

/// Лист «Расходы»: траты по дням месяца, бюджет и обязательные расходы.
class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  String _query = '';
  bool _onlyFilled = false;

  static const _cols = [
    Col(2),
    Col(4),
    Col(3, align: Alignment.centerRight),
    Col(4),
  ];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final e = store.data.expenses;
    final today = dateOnly(DateTime.now());
    final filled = e.days.where((d) => !d.isEmpty).length;
    final q = _query.trim().toLowerCase();
    final days = e.days.where((d) {
      if (_onlyFilled && d.isEmpty) return false;
      if (q.isEmpty) return true;
      return d.name.toLowerCase().contains(q) ||
          d.note.toLowerCase().contains(q);
    }).toList();
    final rest = e.remainder;

    return PageBody(
      children: [
        PageHeader(
          title: 'Расходы',
          subtitle:
              '${monthYear(e.year, e.month)} · траты по дням, как на листе «Расходы»',
          actions: [
            AppButton(
              icon: Icons.arrow_forward_rounded,
              label:
                  'К ${kMonthsDative[DateTime(e.year, e.month + 1).month - 1]}',
              tooltip: 'Перейти к следующему месяцу',
              onPressed: () => _nextMonth(context),
            ),
          ],
        ),
        KpiGrid(
          children: [
            KpiCard(
              title: 'Итого',
              value: fmtCalcMoneyShort(e.total),
              subtitle: filled == 0
                  ? 'Трат пока нет'
                  : '$filled ${plural(filled, 'день', 'дня', 'дней')} с тратами',
            ),
            KpiCard(
              title: 'Бюджет',
              value: '',
              valueWidget: _KpiInput(
                value: e.budget,
                onCommit: (v) => store.edit((_) => e.budget = v),
              ),
              badge: const _EditHint(),
              subtitle: 'Можно формулой: =50000',
            ),
            KpiCard(
              title: 'Остаток',
              value: fmtCalcMoneyShort(rest),
              subtitle: 'Бюджет − Итого',
              subtitleColor: (rest.number ?? 0) < 0 ? AppColors.negative : null,
            ),
            KpiCard(
              title: 'Остаток прошлого месяца',
              value: '',
              valueWidget: _KpiInput(
                value: e.prevRemainder,
                onCommit: (v) => store.edit((_) => e.prevRemainder = v),
              ),
              badge: const _EditHint(),
              subtitle: 'Переносится при смене месяца',
            ),
          ],
        ),
        const SizedBox(height: 32),
        TopAlignedRow(
          flex: const [7, 5],
          children: [
            AppCard(
              titleWidget: Transform.translate(
                offset: const Offset(-8, 0),
                child: CellField(
                  value: e.monthTitle,
                  hint: monthTitle(e.year, e.month),
                  style: AppText.cardTitle,
                  onCommit: (v) => store.edit((_) => e.monthTitle = v),
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Segmented<bool>(
                    items: const [(false, 'Все дни'), (true, 'С тратами')],
                    value: _onlyFilled,
                    onChanged: (v) => setState(() => _onlyFilled = v),
                  ),
                  const SizedBox(width: 12),
                  SearchField(
                    width: 200,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const GridHeader(
                    cols: _cols,
                    labels: ['Дата', 'Наименование', 'Сумма', 'Примечание'],
                  ),
                  if (days.isEmpty)
                    const EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'Ничего не найдено',
                    ),
                  for (final day in days)
                    HoverRow(
                      key: ObjectKey(day),
                      builder: (context, hover) {
                        final isToday = dateOnly(day.date) == today;
                        final weekend = day.date.weekday >= 6;
                        return GridRow(
                          cols: _cols,
                          color: isToday
                              ? AppColors.today
                              : (hover ? AppColors.hover : null),
                          cells: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 26,
                                    child: Text(
                                      '${day.date.day}',
                                      style: AppText.numBold.copyWith(
                                        color: weekend ? AppColors.muted : null,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    weekday(day.date),
                                    style: AppText.small.copyWith(
                                      color: weekend
                                          ? AppColors.negative.withValues(
                                              alpha: 0.7,
                                            )
                                          : null,
                                    ),
                                  ),
                                  if (isToday) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: AppColors.text,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            CellField(
                              value: day.name,
                              hint: hover || isToday ? 'Что купили' : '',
                              onCommit: (v) => store.edit((_) => day.name = v),
                            ),
                            CellField.money(
                              value: day.amount,
                              format: fmtRawMoneyShort,
                              hint: hover || isToday ? '0 ₽' : '',
                              onCommit: (v) =>
                                  store.edit((_) => day.amount = v),
                            ),
                            CellField(
                              value: day.note,
                              hint: hover ? 'Примечание' : '',
                              onCommit: (v) => store.edit((_) => day.note = v),
                            ),
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 12),
                  GridRow(
                    cols: _cols,
                    divider: false,
                    cells: [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('Итого', style: AppText.bodyMedium),
                      ),
                      const SizedBox(),
                      Padding(
                        padding: kNumTotalPad,
                        child: Text(
                          fmtCalcMoneyShort(e.total),
                          style: AppText.numBold,
                        ),
                      ),
                      const SizedBox(),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _MandatoryCard(),
                const SizedBox(height: 24),
                AppCard(
                  title: 'Траты по дням',
                  height: 300,
                  child: DailyBarsChart(daily: e.dailyTotals, month: e.month),
                ),
                const SizedBox(height: 24),
                const _TipsCard(),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _nextMonth(BuildContext context) async {
    final store = StoreScope.read(context);
    final e = store.data.expenses;
    final next = DateTime(e.year, e.month + 1);
    var toDynamics = true;
    var carry = true;
    final total = e.total.number ?? 0;
    final rest = e.remainder.number;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
            'Перейти к месяцу «${monthYear(next.year, next.month)}»?',
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Траты по дням будут очищены, лист заполнится днями нового месяца. '
                  'Бюджет и список обязательных расходов сохранятся (план — да, факт — очистится).',
                  style: AppText.body,
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: toDynamics,
                  onChanged: (v) => setLocal(() => toDynamics = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text(
                    'Записать итог ${fmtMoneyShort(total)} в «Динамику» → ${monthYear(e.year, e.month)}',
                    style: AppText.body,
                  ),
                ),
                CheckboxListTile(
                  value: carry,
                  onChanged: rest == null
                      ? null
                      : (v) => setLocal(() => carry = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text(
                    'Перенести остаток ${rest == null ? '' : fmtMoneyShort(rest)} в «Остаток прошлого месяца»',
                    style: AppText.body,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Совет: перед переходом можно сохранить копию текущего месяца в Excel.',
                  style: AppText.small,
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            AppButton.ghost(
              icon: Icons.download_rounded,
              label: 'Сохранить копию…',
              dense: false,
              onPressed: () => exportExcel(
                context,
                suggestedName: 'Бюджет — ${monthYear(e.year, e.month)}.xlsx',
              ),
            ),
            AppButton(
              label: 'Отмена',
              onPressed: () => Navigator.pop(ctx, false),
            ),
            AppButton.primary(
              label: 'Перейти',
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (go != true || !context.mounted) return;
    store.nextExpenseMonth(writeToDynamics: toDynamics, carryRemainder: carry);
    showUndoSnack(context, 'Начат месяц «${monthYear(next.year, next.month)}»');
  }
}

/// Крупное редактируемое значение в карточке показателя.
class _KpiInput extends StatelessWidget {
  const _KpiInput({required this.value, required this.onCommit});
  final String value;
  final ValueChanged<String> onCommit;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(-10, 0),
      child: CellField.money(
        value: value,
        format: fmtRawMoneyShort,
        hint: '0 ₽',
        align: TextAlign.left,
        style: AppText.kpi,
        dense: true,
        showFormulaBadge: false,
        onCommit: onCommit,
      ),
    );
  }
}

class _EditHint extends StatelessWidget {
  const _EditHint();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Нажмите на сумму, чтобы изменить',
    child: Icon(Icons.edit_outlined, size: 16, color: AppColors.faint),
  );
}

/// «Обязательные расходы в мес.» — правая таблица листа (F1:H8).
class _MandatoryCard extends StatelessWidget {
  const _MandatoryCard();

  static const _cols = [
    Col(6),
    Col(3, align: Alignment.centerRight),
    Col(3, align: Alignment.centerRight),
    Col(0, width: 40, align: Alignment.center),
  ];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final e = store.data.expenses;
    return AppCard(
      title: e.mandatoryTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GridHeader(cols: _cols, labels: ['Статья', 'План', 'Факт', '']),
          for (final m in e.mandatory)
            HoverRow(
              key: ObjectKey(m),
              builder: (context, hover) => GridRow(
                cols: _cols,
                color: hover ? AppColors.hover : null,
                cells: [
                  CellField(
                    value: m.name,
                    hint: 'Статья',
                    onCommit: (v) => store.edit((_) => m.name = v),
                  ),
                  CellField.money(
                    value: m.plan,
                    format: fmtRawMoneyShort,
                    onCommit: (v) => store.edit((_) => m.plan = v),
                  ),
                  CellField.money(
                    value: m.fact,
                    format: fmtRawMoneyShort,
                    onCommit: (v) => store.edit((_) => m.fact = v),
                  ),
                  RowDeleteButton(
                    visible: hover,
                    onPressed: () => store.edit((_) => e.mandatory.remove(m)),
                  ),
                ],
              ),
            ),
          AddRowButton(
            label: 'Добавить статью',
            onPressed: () =>
                store.edit((_) => e.mandatory.add(MandatoryItem())),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.remainder.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(8),
            ),
            child: GridRow(
              cols: _cols,
              divider: false,
              cells: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Сумма', style: AppText.bodyMedium),
                ),
                Padding(
                  padding: kNumTotalPad,
                  child: Text(
                    fmtCalcMoneyShort(e.planTotal),
                    style: AppText.numBold,
                  ),
                ),
                Padding(
                  padding: kNumTotalPad,
                  child: Text(
                    fmtCalcMoneyShort(e.factTotal),
                    style: AppText.numBold,
                  ),
                ),
                const SizedBox(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard();

  @override
  Widget build(BuildContext context) {
    Widget tip(String code, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.subtle,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(code, style: AppText.num.copyWith(fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppText.small)),
        ],
      ),
    );
    return AppCard(
      title: 'Ввод как в Excel',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tip(
            '=1500+300',
            'Несколько трат за день — формулой, она сохранится в Excel',
          ),
          tip('Enter', 'Сохранить ячейку'),
          tip('Tab', 'Сохранить и перейти к следующей ячейке'),
          tip('Esc', 'Отменить правку ячейки'),
          if (Raw.isFormula(StoreScope.of(context).data.expenses.budget))
            tip(
              'ƒ',
              'Значок у суммы — в ячейке формула, наведите, чтобы увидеть',
            ),
        ],
      ),
    );
  }
}

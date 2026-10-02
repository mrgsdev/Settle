import 'package:flutter/material.dart';

import '../../excel/budget_excel.dart' show formatRuDate, parseRuDate;
import '../../model/budget.dart';
import '../../model/calc.dart';
import '../../model/store.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/cells.dart';
import '../widgets/common.dart';

/// Лист «Долги»: кому и сколько должен.
class DebtsPage extends StatelessWidget {
  const DebtsPage({super.key});

  static const _cols = [
    Col(3),
    Col(3, align: Alignment.centerRight),
    Col(4),
    Col(4),
    Col(0, width: 40, align: Alignment.center),
  ];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final d = store.data;
    final debts = d.debts;

    void add() => store.edit(
      (dd) => dd.debts.add(Debt(date: formatRuDate(DateTime.now()))),
    );

    // Группировка по кредиторам
    final byCreditor = <String, double>{};
    for (final debt in debts) {
      final key = debt.creditor.trim().isEmpty
          ? 'Без имени'
          : debt.creditor.trim();
      byCreditor[key] = (byCreditor[key] ?? 0) + Raw.num(debt.amount);
    }
    final creditors = byCreditor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final biggest = debts.isEmpty
        ? null
        : debts.reduce(
            (a, b) => Raw.num(a.amount) >= Raw.num(b.amount) ? a : b,
          );
    final total = d.debtTotal;

    return PageBody(
      children: [
        PageHeader(
          title: 'Долги',
          subtitle: 'Кому и сколько я должен — как на листе «Долги»',
          actions: [
            AppButton.primary(
              icon: Icons.add_rounded,
              label: 'Добавить долг',
              onPressed: add,
            ),
          ],
        ),
        KpiGrid(
          children: [
            KpiCard(
              title: 'Общий долг',
              value: fmtCalcMoney(total),
              subtitle: debts.isEmpty
                  ? 'Долгов нет — отлично'
                  : '${debts.length} ${plural(debts.length, 'запись', 'записи', 'записей')}',
            ),
            KpiCard(
              title: 'Кредиторов',
              value: '${creditors.length}',
              subtitle: creditors.isEmpty
                  ? '—'
                  : 'Больше всего — ${creditors.first.key}',
            ),
            KpiCard(
              title: 'Самый крупный долг',
              value: biggest == null ? '—' : fmtMoney(Raw.num(biggest.amount)),
              subtitle: biggest == null
                  ? '—'
                  : [
                      biggest.creditor,
                      biggest.purpose,
                    ].where((s) => s.trim().isNotEmpty).join(' · '),
            ),
          ],
        ),
        const SizedBox(height: 32),
        TopAlignedRow(
          flex: const [8, 4],
          children: [
            AppCard(
              title: 'Список долгов',
              child: debts.isEmpty
                  ? EmptyState(
                      icon: Icons.handshake_outlined,
                      title: 'Долгов нет',
                      text: 'Когда займёте — запишите здесь, чтобы не забыть',
                      action: AppButton.primary(
                        icon: Icons.add_rounded,
                        label: 'Добавить долг',
                        onPressed: add,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const GridHeader(
                          cols: _cols,
                          labels: [
                            'Дата',
                            'Сумма',
                            'Кому я должен',
                            'На что брал',
                            '',
                          ],
                        ),
                        for (final debt in debts)
                          HoverRow(
                            key: ObjectKey(debt),
                            builder: (context, hover) {
                              final date = parseRuDate(debt.date);
                              return GridRow(
                                cols: _cols,
                                color: hover ? AppColors.hover : null,
                                cells: [
                                  DateCell(
                                    date: date,
                                    hint: debt.date.isEmpty
                                        ? 'Дата'
                                        : debt.date,
                                    onPick: (v) => store.edit(
                                      (_) => debt.date = formatRuDate(v),
                                    ),
                                  ),
                                  CellField.money(
                                    value: debt.amount,
                                    onCommit: (v) =>
                                        store.edit((_) => debt.amount = v),
                                  ),
                                  CellField(
                                    value: debt.creditor,
                                    hint: 'Имя',
                                    onCommit: (v) =>
                                        store.edit((_) => debt.creditor = v),
                                  ),
                                  CellField(
                                    value: debt.purpose,
                                    hint: 'На что',
                                    onCommit: (v) =>
                                        store.edit((_) => debt.purpose = v),
                                  ),
                                  RowDeleteButton(
                                    visible: hover,
                                    tooltip: 'Удалить долг',
                                    onPressed: () {
                                      store.editUndoable(
                                        'Удаление долга',
                                        (dd) => dd.debts.remove(debt),
                                      );
                                      showUndoSnack(context, 'Долг удалён');
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        AddRowButton(label: 'Добавить долг', onPressed: add),
                        const SizedBox(height: 12),
                        GridRow(
                          cols: _cols,
                          divider: false,
                          cells: [
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                'Общий долг',
                                style: AppText.bodyMedium,
                              ),
                            ),
                            Padding(
                              padding: kNumTotalPad,
                              child: Text(
                                fmtCalcMoney(total),
                                style: AppText.numBold,
                              ),
                            ),
                            const SizedBox(),
                            const SizedBox(),
                            const SizedBox(),
                          ],
                        ),
                      ],
                    ),
            ),
            AppCard(
              title: 'По кредиторам',
              child: creditors.isEmpty
                  ? const EmptyState(
                      icon: Icons.people_outline_rounded,
                      title: 'Пока пусто',
                    )
                  : Column(
                      children: [
                        for (final c in creditors) ...[
                          Row(
                            children: [
                              Avatar(c.key, size: 40),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.key,
                                      style: AppText.body,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(3),
                                      child: LinearProgressIndicator(
                                        value: (total.number ?? 0) > 0
                                            ? (c.value / total.number!).clamp(
                                                0.0,
                                                1.0,
                                              )
                                            : 0,
                                        minHeight: 5,
                                        backgroundColor: AppColors.subtle,
                                        color: AppColors.text,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(fmtMoneyShort(c.value), style: AppText.num),
                            ],
                          ),
                          const SizedBox(height: 18),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

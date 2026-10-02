import 'package:flutter/material.dart';

import '../../model/budget.dart';
import '../../model/calc.dart';
import '../../model/store.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/cells.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/menu_button.dart';

/// Лист «Баланс»: блоки месяцев и сводка «Статья · Сумма · Доля».
class BalancePage extends StatelessWidget {
  const BalancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final d = store.data;
    return PageBody(
      children: [
        PageHeader(
          title: 'Баланс',
          subtitle: 'Остатки на счетах по месяцам — как на листе «Баланс»',
          actions: [
            AppButton.primary(
              icon: Icons.add_rounded,
              label: 'Новый месяц',
              onPressed: store.addBalanceMonth,
            ),
          ],
        ),
        TopAlignedRow(
          flex: const [8, 4],
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (d.months.isEmpty)
                  AppCard(
                    child: EmptyState(
                      icon: Icons.calendar_month_outlined,
                      title: 'Пока нет ни одного месяца',
                      text:
                          'Добавьте месяц и перечислите источники: карты, наличные, кошельки',
                      action: AppButton.primary(
                        icon: Icons.add_rounded,
                        label: 'Новый месяц',
                        onPressed: store.addBalanceMonth,
                      ),
                    ),
                  ),
                // Последний месяц — сверху.
                for (var i = d.months.length - 1; i >= 0; i--) ...[
                  _MonthCard(key: ObjectKey(d.months[i]), index: i),
                  if (i > 0) const SizedBox(height: 24),
                ],
              ],
            ),
            const _SharesCard(),
          ],
        ),
      ],
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({super.key, required this.index});
  final int index;

  static const _cols = [
    Col(4),
    Col(3),
    Col(3, align: Alignment.centerRight),
    Col(3),
    Col(0, width: 40, align: Alignment.center),
  ];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final d = store.data;
    final m = d.months[index];
    final saldo = d.saldo(index);
    final change = d.change(index);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Transform.translate(
                  offset: const Offset(-8, 0),
                  child: CellField(
                    value: m.title,
                    hint: BalanceMonth.defaultTitle(m.date),
                    style: AppText.cardTitle,
                    onCommit: (v) => store.edit((_) => m.title = v),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DateCell(
                date: m.date,
                style: AppText.muted,
                onPick: (v) => store.edit((_) => m.date = v),
              ),
              const SizedBox(width: 4),
              MenuButton<String>(
                kind: BtnKind.ghost,
                dense: true,
                tooltip: 'Действия',
                items: () => [
                  menuItem('add', 'Добавить источник', icon: Icons.add_rounded),
                  menuItem(
                    'title',
                    'Заголовок по дате',
                    icon: Icons.title_rounded,
                  ),
                  const PopupMenuDivider(),
                  menuItem(
                    'delete',
                    'Удалить месяц',
                    icon: Icons.delete_outline_rounded,
                    color: AppColors.negative,
                  ),
                ],
                onSelected: (v) async {
                  switch (v) {
                    case 'add':
                      store.edit((_) => m.sources.add(BalanceSource()));
                    case 'title':
                      store.edit(
                        (_) => m.title = BalanceMonth.defaultTitle(m.date),
                      );
                    case 'delete':
                      final ok = await confirm(
                        context,
                        title: 'Удалить месяц?',
                        text:
                            '«${m.title}» и все его источники будут удалены. Действие можно отменить.',
                        ok: 'Удалить',
                      );
                      if (!ok) return;
                      store.editUndoable(
                        'Удаление месяца',
                        (dd) => dd.months.remove(m),
                      );
                      if (context.mounted) {
                        showUndoSnack(context, 'Месяц удалён');
                      }
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          const GridHeader(
            cols: _cols,
            labels: ['Источник', 'Валюта', 'Баланс', 'Статья', ''],
          ),
          for (final s in m.sources)
            HoverRow(
              key: ObjectKey(s),
              builder: (context, hover) => GridRow(
                cols: _cols,
                color: hover ? AppColors.hover : null,
                cells: [
                  CellField(
                    value: s.name,
                    hint: 'Название',
                    onCommit: (v) => store.edit((_) => s.name = v),
                  ),
                  ChoiceCell(
                    value: s.currency,
                    options: kCurrencies,
                    allowCustom: true,
                    customTitle: 'Валюта',
                    onChanged: (v) => store.edit((_) => s.currency = v),
                  ),
                  CellField.money(
                    value: s.balance,
                    onCommit: (v) => store.edit((_) => s.balance = v),
                  ),
                  ChoiceCell(
                    value: s.article,
                    options: kArticles,
                    builder: (v) => ArticlePill(v),
                    onChanged: (v) => store.edit((_) => s.article = v),
                  ),
                  RowDeleteButton(
                    visible: hover,
                    onPressed: () => store.edit((_) => m.sources.remove(s)),
                  ),
                ],
              ),
            ),
          AddRowButton(
            label: 'Добавить источник',
            onPressed: () => store.edit((_) => m.sources.add(BalanceSource())),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Итого',
                  value: fmtCalcMoney(m.total),
                  bg: AppColors.subtle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Stat(
                  label: 'Сальдо',
                  value: saldo == null
                      ? '—'
                      : (saldo.isError
                            ? excelError(saldo.error!)
                            : signed(fmtMoney(saldo.number!), saldo.number!)),
                  hint: saldo == null ? 'нет прошлого месяца' : null,
                  color: saldo?.isError ?? false
                      ? AppColors.negative
                      : signColor(saldo?.number),
                  bg: AppColors.savings,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Tooltip(
                  message:
                      'Как в таблице: (Итого − Итого прошлого месяца) / Итого',
                  child: _Stat(
                    label: 'Изменение в %',
                    value: change == null
                        ? '—'
                        : (change.isError
                              ? excelError(change.error!)
                              : signed(
                                  fmtPercent(change.number!),
                                  change.number!,
                                )),
                    hint: change == null ? 'нет прошлого месяца' : null,
                    color: change?.isError ?? false
                        ? AppColors.negative
                        : signColor(change?.number),
                    bg: AppColors.consumption,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.bg,
    this.color,
    this.hint,
  });
  final String label;
  final String value;
  final Color bg;
  final Color? color;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.small.copyWith(color: AppColors.secondary),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppText.numBold.copyWith(
                fontSize: 18,
                color: color ?? AppColors.text,
              ),
            ),
          ),
          if (hint != null)
            Text(hint!, style: AppText.small.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}

/// «Статья · Сумма · Доля» — правая таблица листа «Баланс» (H2:J6).
class _SharesCard extends StatelessWidget {
  const _SharesCard();

  static const _cols = [
    Col(5),
    Col(4, align: Alignment.centerRight),
    Col(3, align: Alignment.centerRight),
  ];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final d = store.data;
    final source = d.months.lastWhere(
      (m) => (m.total.number ?? 0) != 0,
      orElse: () => d.months.isEmpty ? _none : d.months.last,
    );

    return AppCard(
      title: 'Распределение',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Сколько денег в потреблении, инвестициях и сбережениях.',
            style: AppText.small,
          ),
          const SizedBox(height: 16),
          const GridHeader(cols: _cols, labels: ['Статья', 'Сумма', 'Доля']),
          for (var i = 0; i < d.shares.length; i++)
            GridRow(
              key: ObjectKey(d.shares[i]),
              cols: _cols,
              cells: [
                Row(
                  children: [
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: articleChartColor(d.shares[i].label),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: CellField(
                        value: d.shares[i].label,
                        onCommit: (v) =>
                            store.edit((_) => d.shares[i].label = v),
                      ),
                    ),
                  ],
                ),
                CellField.money(
                  value: d.shares[i].amount,
                  onCommit: (v) => store.edit((_) => d.shares[i].amount = v),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _calcText(d.shareOf(i), percent: true),
                ),
              ],
            ),
          GridRow(
            cols: _cols,
            divider: false,
            cells: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('Итого', style: AppText.bodyMedium),
              ),
              Padding(
                padding: kNumTotalPad,
                child: _calcText(d.sharesTotal, bold: true),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _calcText(d.sharesShareTotal, percent: true, bold: true),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ShareBar(
            parts: [
              for (final s in d.shares)
                (s.label, Raw.num(s.amount), articleChartColor(s.label)),
            ],
          ),
          if (!identical(source, _none)) ...[
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                icon: Icons.auto_awesome_outlined,
                label:
                    'Заполнить из «${kMonths[source.date.month - 1]} ${source.date.year}»',
                dense: true,
                tooltip: 'Сложить балансы источников месяца по статьям',
                onPressed: () => store.fillSharesFrom(source),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static final _none = BalanceMonth(
    title: '',
    date: DateTime(2000),
    sources: [],
  );

  static Widget _calcText(
    CalcValue v, {
    bool percent = false,
    bool bold = false,
  }) {
    final text = percent ? fmtCalcPercent(v) : fmtCalcMoney(v);
    final style = bold ? AppText.numBold : AppText.num;
    return Text(
      text,
      style: v.isError ? style.copyWith(color: AppColors.negative) : style,
      textAlign: TextAlign.right,
    );
  }
}

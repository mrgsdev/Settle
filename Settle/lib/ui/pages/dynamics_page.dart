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

/// Лист «Динамика»: итоги по месяцам для нескольких лет.
class DynamicsPage extends StatelessWidget {
  const DynamicsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final dyn = store.data.dynamics;
    final years = dyn.years;
    final cols = [
      const Col(3),
      for (final _ in years) const Col(3, align: Alignment.centerRight),
    ];

    final series = [
      for (final y in years)
        DynamicsYearSeries(y.year, [
          for (final v in y.values) Raw.eval(v)?.number,
        ]),
    ];

    return PageBody(
      children: [
        PageHeader(
          title: 'Динамика',
          subtitle: 'Итоги по месяцам и годам — как на листе «Динамика»',
          actions: [
            AppButton.primary(
              icon: Icons.add_rounded,
              label: 'Добавить год',
              onPressed: store.addDynamicsYear,
            ),
          ],
        ),
        if (years.isNotEmpty) ...[
          KpiGrid(
            children: [
              for (final y in years.reversed.take(3).toList().reversed)
                _yearKpi(y, years),
            ],
          ),
          const SizedBox(height: 32),
        ],
        TopAlignedRow(
          flex: const [5, 7],
          children: [
            AppCard(
              child: years.isEmpty
                  ? EmptyState(
                      icon: Icons.table_chart_outlined,
                      title: 'Нет ни одного года',
                      action: AppButton.primary(
                        icon: Icons.add_rounded,
                        label: 'Добавить год',
                        onPressed: store.addDynamicsYear,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GridRow(
                          cols: cols,
                          height: 40,
                          cells: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Text(dyn.header, style: AppText.header),
                            ),
                            for (final y in years) _YearHeader(year: y),
                          ],
                        ),
                        for (var m = 0; m < 12; m++)
                          HoverRow(
                            builder: (context, hover) => GridRow(
                              cols: cols,
                              height: 44,
                              color: hover ? AppColors.hover : null,
                              cells: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Text(kMonths[m], style: AppText.body),
                                ),
                                for (final y in years)
                                  CellField.money(
                                    key: ValueKey('${identityHashCode(y)}-$m'),
                                    value: y.values[m],
                                    onCommit: (v) =>
                                        store.edit((_) => y.values[m] = v),
                                  ),
                              ],
                            ),
                          ),
                        GridRow(
                          cols: cols,
                          divider: false,
                          cells: [
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Tooltip(
                                message:
                                    'Как в таблице: среднее за заполненные месяцы (AVERAGE)',
                                child: Text('Итого', style: AppText.bodyMedium),
                              ),
                            ),
                            for (final y in years)
                              Padding(
                                padding: kNumTotalPad,
                                child: Text(
                                  fmtCalcMoney(y.average),
                                  style: AppText.numBold.copyWith(
                                    color: y.average.isError
                                        ? AppColors.negative
                                        : null,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Padding(
                          padding: EdgeInsets.only(left: 8, top: 4),
                          child: Text(
                            '«Итого» — среднее в месяц, как формула AVERAGE в таблице',
                            style: AppText.small,
                          ),
                        ),
                      ],
                    ),
            ),
            AppCard(
              title: 'Сравнение по годам',
              trailing: Wrap(
                spacing: 16,
                children: [
                  for (var i = 0; i < years.length; i++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: YearsBarsChart.colorFor(i, years.length),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${years[i].year}',
                          style: AppText.small.copyWith(color: AppColors.text),
                        ),
                      ],
                    ),
                ],
              ),
              height: 560,
              child: years.isEmpty
                  ? const SizedBox()
                  : YearsBarsChart(years: series),
            ),
          ],
        ),
      ],
    );
  }

  Widget _yearKpi(DynamicsYear y, List<DynamicsYear> all) {
    final values = [
      for (final v in y.values) Raw.eval(v)?.number,
    ].whereType<double>().toList();
    final sum = values.fold<double>(0, (a, b) => a + b);
    final prev = all.where((x) => x.year == y.year - 1).firstOrNull;
    String subtitle;
    Color? color;
    if (values.isEmpty) {
      subtitle = 'Месяцы не заполнены';
    } else if (prev != null &&
        !prev.average.isError &&
        !y.average.isError &&
        prev.average.number! != 0) {
      final diff = y.average.number! / prev.average.number! - 1;
      subtitle = '${signed(fmtPercent(diff), diff)} к ${prev.year} в среднем';
      color = signColor(diff);
    } else {
      subtitle =
          'Сумма за ${values.length} ${plural(values.length, 'месяц', 'месяца', 'месяцев')}: ${fmtMoneyInt(sum)}';
    }
    return KpiCard(
      title: 'В среднем за ${y.year}',
      value: fmtCalcMoneyShort(y.average),
      subtitle: subtitle,
      subtitleColor: color,
    );
  }
}

class _YearHeader extends StatelessWidget {
  const _YearHeader({required this.year});
  final DynamicsYear year;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.read(context);
    return MenuButton<String>(
      kind: BtnKind.ghost,
      dense: true,
      icon: null,
      label: '${year.year}',
      items: () => [
        menuItem('edit', 'Изменить год', icon: Icons.edit_outlined),
        const PopupMenuDivider(),
        menuItem(
          'delete',
          'Удалить столбец',
          icon: Icons.delete_outline_rounded,
          color: AppColors.negative,
        ),
      ],
      onSelected: (v) async {
        if (v == 'edit') {
          final text = await promptText(
            context,
            title: 'Год',
            initial: '${year.year}',
          );
          final y = int.tryParse(text ?? '');
          if (y != null && y > 1900 && y < 2200) {
            store.edit((_) => year.year = y);
          }
        } else {
          final ok = await confirm(
            context,
            title: 'Удалить ${year.year} год?',
            text:
                'Столбец со всеми значениями будет удалён. Действие можно отменить.',
            ok: 'Удалить',
          );
          if (!ok || !context.mounted) return;
          store.editUndoable(
            'Удаление года',
            (d) => d.dynamics.years.remove(year),
          );
          showUndoSnack(context, 'Столбец ${year.year} удалён');
        }
      },
    );
  }
}

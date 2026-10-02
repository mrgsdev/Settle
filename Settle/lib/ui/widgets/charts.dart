import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../model/budget.dart';
import '../format.dart';
import '../theme.dart';

/// «Красивый» шаг сетки: 1, 2, 2.5, 5 × 10ⁿ.
double niceStep(double range, [int ticks = 5]) {
  if (range <= 0) return 1;
  final raw = range / ticks;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final n = raw / mag;
  final step = n <= 1
      ? 1.0
      : (n <= 2 ? 2.0 : (n <= 2.5 ? 2.5 : (n <= 5 ? 5.0 : 10.0)));
  return step * mag;
}

(double, double) niceMax(double maxValue, {double fallback = 1000}) {
  final m = maxValue <= 0 ? fallback : maxValue;
  final step = niceStep(m);
  final top = (m / step).ceil() * step;
  return (top == m ? top + step : top, step);
}

Widget _leftTitle(double value, TitleMeta meta) {
  if (value == meta.max &&
      value != meta.min &&
      meta.appliedInterval > 0 &&
      value % meta.appliedInterval != 0) {
    return const SizedBox();
  }
  return SideTitleWidget(
    meta: meta,
    space: 10,
    child: Text(fmtAxis(value), style: AppText.axis),
  );
}

FlGridData _grid(double step) => FlGridData(
  show: true,
  drawVerticalLine: false,
  horizontalInterval: step,
  getDrawingHorizontalLine: (_) =>
      FlLine(color: AppColors.chartGrid, strokeWidth: 1),
);

const _noTitles = AxisTitles(sideTitles: SideTitles(showTitles: false));

/// Накопительная линия трат за месяц с отметкой последней точки (как в референсе).
class CumulativeSpendChart extends StatelessWidget {
  const CumulativeSpendChart({
    super.key,
    required this.sheet,
    required this.daily,
    this.budget,
  });

  final ExpenseSheet sheet;
  final List<double> daily;
  final double? budget;

  @override
  Widget build(BuildContext context) {
    final n = daily.length;
    if (n == 0) return const SizedBox();
    final now = DateTime.now();
    final lastEntry = daily.lastIndexWhere((v) => v != 0) + 1;
    int end;
    final monthKey = sheet.year * 12 + sheet.month;
    final nowKey = now.year * 12 + now.month;
    if (monthKey < nowKey) {
      end = n;
    } else if (monthKey == nowKey) {
      end = math.max(now.day, lastEntry);
    } else {
      end = math.max(lastEntry, 1);
    }
    end = end.clamp(2, n);

    final spots = <FlSpot>[];
    var acc = 0.0;
    for (var d = 1; d <= end; d++) {
      acc += daily[d - 1];
      spots.add(FlSpot(d.toDouble(), acc));
    }
    final maxSpend = spots.map((s) => s.y).fold<double>(0, math.max);
    final b = budget ?? 0;
    final showBudget = b > 0 && b <= math.max(maxSpend, 1) * 1.6;
    final (maxY, step) = niceMax(
      math.max(maxSpend, showBudget ? b : 0),
      fallback: b > 0 ? b : 10000,
    );
    final lastSpot = spots.last;

    return LineChart(
      LineChartData(
        minX: 1,
        maxX: n.toDouble(),
        minY: 0,
        maxY: maxY,
        clipData: const FlClipData.none(),
        gridData: _grid(step),
        borderData: FlBorderData(
          show: true,
          border: Border(bottom: BorderSide(color: AppColors.chartGrid)),
        ),
        titlesData: FlTitlesData(
          topTitles: _noTitles,
          rightTitles: _noTitles,
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 64,
              interval: step,
              getTitlesWidget: _leftTitle,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final d = v.round();
                if (v != d.toDouble()) return const SizedBox();
                final show = d == 1 || (d % 5 == 0 && n - d >= 2) || d == n;
                if (!show) return const SizedBox();
                final label = d == 1
                    ? '1 ${kMonthsShort[sheet.month - 1].toLowerCase()}'
                    : '$d';
                return SideTitleWidget(
                  meta: meta,
                  space: 8,
                  child: Text(label, style: AppText.axis),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (showBudget)
              HorizontalLine(
                y: b,
                color: AppColors.faint,
                strokeWidth: 1.2,
                dashArray: [6, 5],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.only(bottom: 4),
                  style: AppText.axis,
                  labelResolver: (_) => 'Бюджет ${fmtMoneyInt(b)}',
                ),
              ),
          ],
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          getTouchedSpotIndicator: (bar, idx) => [
            for (final _ in idx)
              TouchedSpotIndicatorData(
                FlLine(
                  color: AppColors.chartSecondary,
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
                FlDotData(
                  getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                    radius: 4.5,
                    color: AppColors.text,
                    strokeWidth: 0,
                  ),
                ),
              ),
          ],
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.text,
            tooltipBorderRadius: BorderRadius.circular(8),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${s.x.round()} ${kMonthsGenitive[sheet.month - 1]}\n',
                  TextStyle(
                    color: AppColors.chartSecondary,
                    fontSize: 12,
                    fontFamily: 'Inter',
                  ),
                  children: [
                    TextSpan(
                      text: fmtMoneyShort(s.y),
                      style: TextStyle(
                        color: AppColors.onPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                      ),
                    ),
                    if (daily[s.x.round() - 1] != 0)
                      TextSpan(
                        text:
                            '\n+${fmtMoneyShort(daily[s.x.round() - 1])} за день',
                        style: TextStyle(
                          color: AppColors.chartSecondary,
                          fontSize: 12,
                          fontFamily: 'Inter',
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: AppColors.text,
            barWidth: 2.6,
            isStrokeCapRound: true,
            isStrokeJoinRound: true,
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.chartArea,
                  AppColors.chartArea.withValues(alpha: 0),
                ],
              ),
            ),
            dotData: FlDotData(
              show: true,
              checkToShowDot: (s, _) => s == lastSpot,
              getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                radius: 5,
                color: AppColors.text,
                strokeWidth: 16,
                strokeColor: AppColors.text.withValues(alpha: 0.09),
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 250),
    );
  }
}

/// Столбики по месяцам одного года (нижний правый график референса).
class MonthBarsChart extends StatelessWidget {
  const MonthBarsChart({super.key, required this.values, required this.year});
  final List<double?> values;
  final int year;

  @override
  Widget build(BuildContext context) {
    final maxV = values.whereType<double>().fold<double>(0, math.max);
    final (maxY, step) = niceMax(maxV, fallback: 10000);
    return LayoutBuilder(
      builder: (context, c) {
        final barW = ((c.maxWidth - 70) / 12 * 0.6).clamp(10.0, 34.0);
        return BarChart(
          BarChartData(
            maxY: maxY,
            minY: 0,
            alignment: BarChartAlignment.spaceAround,
            gridData: _grid(step),
            borderData: FlBorderData(
              show: true,
              border: Border(bottom: BorderSide(color: AppColors.chartGrid)),
            ),
            titlesData: FlTitlesData(
              topTitles: _noTitles,
              rightTitles: _noTitles,
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 64,
                  interval: step,
                  getTitlesWidget: _leftTitle,
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (v, meta) => SideTitleWidget(
                    meta: meta,
                    space: 8,
                    child: Text(kMonthsShort[v.toInt()], style: AppText.axis),
                  ),
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.text,
                tooltipBorderRadius: BorderRadius.circular(8),
                tooltipPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                getTooltipItem: (g, gi, rod, ri) {
                  final v = values[g.x];
                  return BarTooltipItem(
                    '${kMonths[g.x]} $year\n',
                    TextStyle(
                      color: AppColors.chartSecondary,
                      fontSize: 12,
                      fontFamily: 'Inter',
                    ),
                    children: [
                      TextSpan(
                        text: v == null ? 'нет данных' : fmtMoneyShort(v),
                        style: TextStyle(
                          color: AppColors.onPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            barGroups: [
              for (var i = 0; i < 12; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: values[i] ?? 0,
                      width: barW,
                      color: AppColors.text,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          duration: const Duration(milliseconds: 250),
        );
      },
    );
  }
}

/// Сгруппированные столбики: месяцы × годы (лист «Динамика»).
class YearsBarsChart extends StatelessWidget {
  const YearsBarsChart({super.key, required this.years});
  final List<DynamicsYearSeries> years;

  static List<Color> get palette => AppColors.chartSeries;

  static Color colorFor(int index, int count) =>
      palette[(count - 1 - index) % palette.length];

  @override
  Widget build(BuildContext context) {
    final maxV = years
        .expand((y) => y.values)
        .whereType<double>()
        .fold<double>(0, math.max);
    final (maxY, step) = niceMax(maxV, fallback: 10000);
    return LayoutBuilder(
      builder: (context, c) {
        final groupW = (c.maxWidth - 70) / 12 * 0.7;
        final rodW = (groupW / math.max(years.length, 1) - 2).clamp(4.0, 22.0);
        return BarChart(
          BarChartData(
            maxY: maxY,
            minY: 0,
            alignment: BarChartAlignment.spaceAround,
            gridData: _grid(step),
            borderData: FlBorderData(
              show: true,
              border: Border(bottom: BorderSide(color: AppColors.chartGrid)),
            ),
            titlesData: FlTitlesData(
              topTitles: _noTitles,
              rightTitles: _noTitles,
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 64,
                  interval: step,
                  getTitlesWidget: _leftTitle,
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (v, meta) => SideTitleWidget(
                    meta: meta,
                    space: 8,
                    child: Text(kMonthsShort[v.toInt()], style: AppText.axis),
                  ),
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.text,
                tooltipBorderRadius: BorderRadius.circular(8),
                tooltipPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                getTooltipItem: (g, gi, rod, ri) {
                  final y = years[ri];
                  final v = y.values[g.x];
                  return BarTooltipItem(
                    '${kMonths[g.x]} ${y.year}\n',
                    TextStyle(
                      color: AppColors.chartSecondary,
                      fontSize: 12,
                      fontFamily: 'Inter',
                    ),
                    children: [
                      TextSpan(
                        text: v == null ? 'нет данных' : fmtMoneyShort(v),
                        style: TextStyle(
                          color: AppColors.onPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            barGroups: [
              for (var m = 0; m < 12; m++)
                BarChartGroupData(
                  x: m,
                  barsSpace: 3,
                  barRods: [
                    for (var i = 0; i < years.length; i++)
                      BarChartRodData(
                        toY: years[i].values[m] ?? 0,
                        width: rodW,
                        color: colorFor(i, years.length),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          duration: const Duration(milliseconds: 250),
        );
      },
    );
  }
}

class DynamicsYearSeries {
  final int year;
  final List<double?> values;
  const DynamicsYearSeries(this.year, this.values);
}

/// Траты по дням — компактные столбики.
class DailyBarsChart extends StatelessWidget {
  const DailyBarsChart({super.key, required this.daily, required this.month});
  final List<double> daily;
  final int month;

  @override
  Widget build(BuildContext context) {
    final maxV = daily.fold<double>(0, math.max);
    final (maxY, step) = niceMax(maxV, fallback: 5000);
    final today = DateTime.now();
    return LayoutBuilder(
      builder: (context, c) {
        final w = ((c.maxWidth - 60) / math.max(daily.length, 1) * 0.55).clamp(
          3.0,
          14.0,
        );
        return BarChart(
          BarChartData(
            maxY: maxY,
            minY: 0,
            alignment: BarChartAlignment.spaceBetween,
            gridData: _grid(step),
            borderData: FlBorderData(
              show: true,
              border: Border(bottom: BorderSide(color: AppColors.chartGrid)),
            ),
            titlesData: FlTitlesData(
              topTitles: _noTitles,
              rightTitles: _noTitles,
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 56,
                  interval: step,
                  getTitlesWidget: _leftTitle,
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  getTitlesWidget: (v, meta) {
                    final d = v.toInt() + 1;
                    final show =
                        d == 1 ||
                        (d % 5 == 0 && daily.length - d >= 2) ||
                        d == daily.length;
                    return show
                        ? SideTitleWidget(
                            meta: meta,
                            space: 6,
                            child: Text('$d', style: AppText.axis),
                          )
                        : const SizedBox();
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.text,
                tooltipBorderRadius: BorderRadius.circular(8),
                tooltipPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                  '${g.x + 1} ${kMonthsGenitive[month - 1]}\n',
                  TextStyle(
                    color: AppColors.chartSecondary,
                    fontSize: 12,
                    fontFamily: 'Inter',
                  ),
                  children: [
                    TextSpan(
                      text: fmtMoneyShort(daily[g.x]),
                      style: TextStyle(
                        color: AppColors.onPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < daily.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: daily[i],
                      width: w,
                      color: today.month == month && today.day == i + 1
                          ? AppColors.muted
                          : AppColors.text,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(2),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          duration: const Duration(milliseconds: 250),
        );
      },
    );
  }
}

/// Горизонтальная полоса долей с легендой (распределение по статьям).
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.parts});
  final List<(String label, double value, Color color)> parts;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<double>(0, (s, p) => s + (p.$2 > 0 ? p.$2 : 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: total <= 0
                ? Container(color: AppColors.subtle)
                : Row(
                    children: [
                      for (final p in parts)
                        if (p.$2 > 0)
                          Expanded(
                            flex: math.max(1, (p.$2 / total * 1000).round()),
                            child: Container(
                              margin: const EdgeInsets.only(right: 2),
                              color: p.$3,
                            ),
                          ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            for (final p in parts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: p.$3,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    p.$1,
                    style: AppText.small.copyWith(color: AppColors.text),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    total > 0 ? fmtPercent(p.$2 > 0 ? p.$2 / total : 0) : '—',
                    style: AppText.small,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Насыщенные цвета статей для графиков.
Color articleChartColor(String article) {
  final a = article.trim().toLowerCase();
  if (a.startsWith('потреб')) return const Color(0xFFF4B084);
  if (a.startsWith('сбереж')) return const Color(0xFF9DC3E6);
  if (a.startsWith('инвест')) return AppColors.investmentsChart;
  return AppColors.chartSecondary;
}

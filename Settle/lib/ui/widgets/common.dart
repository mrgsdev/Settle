import 'package:flutter/material.dart';

import '../../model/store.dart';

import '../format.dart';
import '../theme.dart';

/// Значок приложения (тот же, что у exe и в установщике).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 30});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/settle.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// Карточка с тонкой рамкой, как в референсе.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.title,
    this.titleWidget,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.height,
  });

  final String? title;

  /// Заголовок-виджет вместо текста — например, редактируемое поле.
  final Widget? titleWidget;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: height == null ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (title != null || titleWidget != null || trailing != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 34),
              child: Row(
                children: [
                  if (titleWidget != null)
                    Expanded(child: titleWidget!)
                  else if (title != null)
                    Expanded(
                      child: Text(
                        title!,
                        style: AppText.cardTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                  ?trailing,
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (height == null) child else Expanded(child: child),
        ],
      ),
    );
  }
}

/// Карточка показателя: заголовок, крупное значение, подпись.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.subtitleColor,
    this.valueWidget,
    this.badge,
  });

  final String title;
  final String value;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? valueWidget;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 22,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppText.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ?badge,
              ],
            ),
          ),
          const SizedBox(height: 14),
          valueWidget ??
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: AppText.kpi, maxLines: 1),
              ),
          const SizedBox(height: 12),
          Text(
            subtitle ?? '',
            style: AppText.muted.copyWith(
              color: subtitleColor ?? AppColors.muted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Сегментированный переключатель («Tab Tab Tab» из референса).
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.subtle,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label) in items)
            _Segment(
              label: label,
              selected: v == value,
              onTap: () => onChanged(v),
            ),
        ],
      ),
    );
  }
}

/// Выбор из длинного списка (месяцы, годы): стрелки «раньше / позже»
/// и меню со всеми значениями. [items] — от старых к новым.
class StepPicker<T> extends StatelessWidget {
  const StepPicker({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final i = items.indexWhere((e) => e.$1 == value);
    Widget arrow(IconData icon, String tooltip, int to) {
      final enabled = to >= 0 && to < items.length;
      return IconButton(
        tooltip: enabled ? tooltip : null,
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        color: AppColors.text,
        disabledColor: AppColors.faint,
        icon: Icon(icon),
        onPressed: enabled ? () => onChanged(items[to].$1) : null,
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.subtle,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          arrow(Icons.chevron_left_rounded, 'Раньше', i - 1),
          PopupMenuButton<T>(
            tooltip: 'Выбрать из списка',
            initialValue: value,
            position: PopupMenuPosition.under,
            constraints: const BoxConstraints(minWidth: 180, maxHeight: 420),
            onSelected: onChanged,
            itemBuilder: (_) => [
              for (final (v, label) in items.reversed)
                PopupMenuItem<T>(
                  value: v,
                  height: 36,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: v == value
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              decoration: BoxDecoration(
                color: AppColors.raised,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    i >= 0 ? items[i].$2 : '',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
          arrow(Icons.chevron_right_rounded, 'Позже', i + 1),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.raised : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: selected ? AppColors.text : AppColors.secondary,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

enum BtnKind { primary, secondary, ghost }

/// Кнопка в стиле референса: чёрная «Share» и серая «•••».
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    this.label,
    this.icon,
    required this.onPressed,
    this.kind = BtnKind.secondary,
    this.tooltip,
    this.dense = false,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final BtnKind kind;
  final String? tooltip;
  final bool dense;

  const AppButton.primary({
    super.key,
    this.label,
    this.icon,
    required this.onPressed,
    this.tooltip,
    this.dense = false,
  }) : kind = BtnKind.primary;

  const AppButton.ghost({
    super.key,
    this.label,
    this.icon,
    required this.onPressed,
    this.tooltip,
    this.dense = true,
  }) : kind = BtnKind.ghost;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final (bg, fg) = switch (widget.kind) {
      BtnKind.primary => (
        _hover ? AppColors.primaryHover : AppColors.text,
        AppColors.onPrimary,
      ),
      BtnKind.secondary => (
        _hover ? AppColors.secondaryHover : AppColors.subtle,
        AppColors.text,
      ),
      BtnKind.ghost => (
        _hover ? AppColors.subtle : Colors.transparent,
        AppColors.text,
      ),
    };
    final h = widget.dense ? 34.0 : 40.0;
    final onlyIcon = widget.label == null;
    Widget child = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: h,
      constraints: BoxConstraints(minWidth: onlyIcon ? h : 0),
      padding: EdgeInsets.symmetric(
        horizontal: onlyIcon ? 0 : (widget.dense ? 12 : 16),
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.icon != null)
            Icon(widget.icon, size: widget.dense ? 17 : 18, color: fg),
          if (widget.icon != null && !onlyIcon) const SizedBox(width: 8),
          if (!onlyIcon)
            Text(
              widget.label!,
              style: TextStyle(
                color: fg,
                fontSize: widget.dense ? 14 : 15,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
    child = Opacity(opacity: enabled ? 1 : 0.4, child: child);
    child = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onPressed, child: child),
    );
    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }
    return child;
  }
}

/// Плашка статьи с цветом заливки из исходного Excel.
class ArticlePill extends StatelessWidget {
  const ArticlePill(this.article, {super.key});
  final String article;

  static (Color, Color) colors(String article) {
    final a = article.trim().toLowerCase();
    if (a.startsWith('потреб')) {
      return (AppColors.consumption, AppColors.consumptionInk);
    }
    if (a.startsWith('сбереж')) {
      return (AppColors.savings, AppColors.savingsInk);
    }
    return (AppColors.investments, AppColors.investmentsInk);
  }

  @override
  Widget build(BuildContext context) {
    if (article.trim().isEmpty) {
      return Text('—', style: TextStyle(color: AppColors.faint));
    }
    final (bg, fg) = colors(article);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        article,
        style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w500),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Кружок с инициалами вместо фото из референса.
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 44});
  final String name;
  final double size;

  static List<(Color, Color)> get _palette => AppColors.avatars;

  @override
  Widget build(BuildContext context) {
    final hash = name.codeUnits.fold<int>(
      7,
      (h, c) => (h * 31 + c) & 0x7fffffff,
    );
    final (bg, fg) = _palette[hash % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        initials(name),
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.34,
        ),
      ),
    );
  }
}

/// Заголовок страницы с действиями справа.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.pageTitle),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(subtitle!, style: AppText.muted),
                ],
              ],
            ),
          ),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            actions[i],
          ],
        ],
      ),
    );
  }
}

/// Прокручиваемое тело страницы с ограничением ширины.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 32, 40, 56),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// Ряд колонок, который на узком окне складывается в столбец.
class ResponsiveRow extends StatelessWidget {
  const ResponsiveRow({
    super.key,
    required this.children,
    this.flex,
    this.gap = 24,
    this.breakpoint = 980,
  });
  final List<Widget> children;
  final List<int>? flex;
  final double gap;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                children[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(flex: flex?[i] ?? 1, child: children[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Ряд колонок без IntrinsicHeight — для блоков с таблицами переменной высоты.
class TopAlignedRow extends StatelessWidget {
  const TopAlignedRow({
    super.key,
    required this.children,
    this.flex,
    this.gap = 24,
    this.breakpoint = 1080,
  });
  final List<Widget> children;
  final List<int>? flex;
  final double gap;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(flex: flex?[i] ?? 1, child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// Сетка карточек показателей.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth >= 1100
            ? children.length
            : (c.maxWidth >= 640 ? 2 : 1);
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += perRow) {
          final chunk = children.sublist(
            i,
            (i + perRow).clamp(0, children.length),
          );
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < perRow; j++) ...[
                    if (j > 0) const SizedBox(width: 24),
                    Expanded(
                      child: j < chunk.length ? chunk[j] : const SizedBox(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 24),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}

/// Колонка табличной сетки.
class Col {
  const Col(this.flex, {this.align = Alignment.centerLeft, this.width});
  final int flex;
  final Alignment align;
  final double? width;

  bool get right => align == Alignment.centerRight;
}

/// Строка таблицы: ячейки раскладываются по общим колонкам.
class GridRow extends StatelessWidget {
  const GridRow({
    super.key,
    required this.cols,
    required this.cells,
    this.height = 48,
    this.divider = true,
    this.color,
    this.padding = EdgeInsets.zero,
  });
  final List<Col> cols;
  final List<Widget> cells;
  final double height;
  final bool divider;
  final Color? color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: height),
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: divider
            ? Border(bottom: BorderSide(color: AppColors.divider))
            : null,
      ),
      child: Row(
        children: [
          for (var i = 0; i < cols.length; i++)
            if (cols[i].width != null)
              SizedBox(
                width: cols[i].width,
                child: Align(alignment: cols[i].align, child: cells[i]),
              )
            else
              Expanded(
                flex: cols[i].flex,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Align(alignment: cols[i].align, child: cells[i]),
                ),
              ),
        ],
      ),
    );
  }
}

/// Заголовок таблицы (серые подписи колонок).
class GridHeader extends StatelessWidget {
  const GridHeader({super.key, required this.cols, required this.labels});
  final List<Col> cols;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return GridRow(
      cols: cols,
      height: 36,
      cells: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              labels[i],
              style: AppText.header,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

/// Строка, подсвечивающаяся при наведении; builder получает флаг наведения.
class HoverRow extends StatefulWidget {
  const HoverRow({super.key, required this.builder});
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: widget.builder(context, _hover),
    );
  }
}

/// Кнопка удаления строки — видна при наведении на строку.
class RowDeleteButton extends StatelessWidget {
  const RowDeleteButton({
    super.key,
    required this.visible,
    required this.onPressed,
    this.tooltip = 'Удалить строку',
  });
  final bool visible;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: visible ? 1 : 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AppButton.ghost(
          icon: Icons.close_rounded,
          onPressed: onPressed,
          tooltip: tooltip,
        ),
      ),
    );
  }
}

/// Кнопка «+ Добавить …» под таблицей.
class AddRowButton extends StatelessWidget {
  const AddRowButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppButton.ghost(
          icon: Icons.add_rounded,
          label: label,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// Строка «подпись — значение» для итогов под таблицей.
class TotalLine extends StatelessWidget {
  const TotalLine({
    super.key,
    required this.label,
    required this.value,
    this.bold = false,
    this.color,
    this.fill,
    this.trailing,
  });
  final String label;
  final Widget value;
  final bool bold;
  final Color? color;
  final Color? fill;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: fill != null ? BorderRadius.circular(8) : null,
      ),
      child: Row(
        children: [
          if (fill != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color ?? AppColors.text,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              style: bold
                  ? AppText.bodyMedium.copyWith(fontWeight: FontWeight.w600)
                  : AppText.body,
            ),
          ),
          value,
          ?trailing,
        ],
      ),
    );
  }
}

/// Пустое состояние.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.text,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.subtle,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          Text(title, style: AppText.bodyMedium, textAlign: TextAlign.center),
          if (text != null) ...[
            const SizedBox(height: 4),
            Text(text!, style: AppText.small, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Цвет для положительных/отрицательных изменений.
Color signColor(double? v) {
  if (v == null || v == 0) return AppColors.muted;
  return v > 0 ? AppColors.positive : AppColors.negative;
}

String signed(String s, double v) => v > 0 ? '+$s' : s;

/// Диалог подтверждения.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String text,
  String ok = 'Продолжить',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Text(text, style: AppText.body),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        AppButton(label: 'Отмена', onPressed: () => Navigator.pop(ctx, false)),
        AppButton.primary(label: ok, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return r ?? false;
}

/// Короткое уведомление внизу окна.
void showSnack(
  BuildContext context,
  String text, {
  String? action,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 5),
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        duration: duration,
        action: action == null
            ? null
            : SnackBarAction(label: action, onPressed: onAction ?? () {}),
      ),
    );
}

/// Уведомление с кнопкой «Отменить» для последнего действия.
void showUndoSnack(BuildContext context, String text) {
  final store = StoreScope.read(context);
  showSnack(
    context,
    text,
    action: 'Отменить',
    onAction: store.undo,
    duration: const Duration(seconds: 8),
  );
}

/// Отступы для итоговых чисел под колонками с редактируемыми суммами
/// (чтобы цифры стояли ровно под цифрами ячеек).
const kNumTotalPad = EdgeInsets.only(left: 8, right: 11);

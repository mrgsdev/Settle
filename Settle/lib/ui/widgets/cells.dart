import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../model/calc.dart';
import '../format.dart';
import '../theme.dart';
import 'common.dart';

/// Редактируемая ячейка таблицы.
///
/// Вне фокуса показывает отформатированное значение (например, «1 800 ₽»),
/// в фокусе — то, что хранится в ячейке («=1500+300»). Enter/уход фокуса —
/// сохранить, Esc — отменить правку. Tab переходит к следующей ячейке.
class CellField extends StatefulWidget {
  const CellField({
    super.key,
    required this.value,
    required this.onCommit,
    this.format,
    this.hint = '',
    this.align = TextAlign.left,
    this.style,
    this.numeric = false,
    this.dense = false,
    this.showFormulaBadge = true,
  });

  /// Ячейка суммы: принимает числа и формулы, показывает деньги.
  const CellField.money({
    super.key,
    required this.value,
    required this.onCommit,
    this.format = fmtRawMoney,
    this.hint = '—',
    this.align = TextAlign.right,
    this.style,
    this.dense = false,
    this.showFormulaBadge = true,
  }) : numeric = true;

  final String value;
  final ValueChanged<String> onCommit;
  final String Function(String raw)? format;
  final String hint;
  final TextAlign align;
  final TextStyle? style;
  final bool numeric;

  /// Без вертикальных отступов — для крупных значений в карточках.
  final bool dense;

  /// Значок «ƒ» у ячеек с формулой.
  final bool showFormulaBadge;

  @override
  State<CellField> createState() => _CellFieldState();
}

class _CellFieldState extends State<CellField> {
  late final TextEditingController _c = TextEditingController(text: _display());
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey)
    ..addListener(_onFocus);

  String _display() {
    final v = widget.value;
    if (v.trim().isEmpty || widget.format == null) return v;
    return widget.format!(v);
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _c.text = widget.value;
      _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
    } else {
      _commit();
      _invalid = false;
      _c.text = _display();
    }
    if (mounted) setState(() {});
  }

  /// Ввод не считается (например «5++»): Enter не принимает его.
  bool _invalid = false;

  String _normalized() =>
      widget.numeric ? Raw.normalize(_c.text) : _c.text.trim();

  /// Сумма — пусто, число или формула, которая считается без ошибок.
  static bool _valid(String raw) {
    if (raw.isEmpty) return true;
    final v = Raw.eval(raw);
    return v != null && !v.isError;
  }

  void _commit() {
    final v = _normalized();
    if (v == widget.value) return;
    if (widget.numeric && !_valid(v)) {
      showSnack(
        context,
        'Не получилось посчитать «${_c.text.trim()}» — значение не изменено',
      );
      return;
    }
    widget.onCommit(v);
  }

  void _submit() {
    if (widget.numeric && !_valid(_normalized())) {
      setState(() => _invalid = true);
      return;
    }
    _focus.unfocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      _c.text = widget.value;
      _invalid = false;
      node.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didUpdateWidget(CellField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus &&
        (old.value != widget.value || old.format != widget.format)) {
      _c.text = _display();
    }
  }

  @override
  void dispose() {
    // Поле убрали из дерева во время правки (например, переключили вкладку) —
    // сохраняем введённое после завершения текущего кадра.
    if (_focus.hasFocus) {
      final v = _normalized();
      if (v != widget.value && (!widget.numeric || _valid(v))) {
        final commit = widget.onCommit;
        Future.microtask(() => commit(v));
      }
    }
    _focus.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final isFormula = Raw.isFormula(widget.value);
    final calc = widget.numeric ? Raw.eval(widget.value) : null;
    final isError = calc?.isError ?? false;
    final base = widget.style ?? (widget.numeric ? AppText.num : AppText.body);
    final style = isError && !focused
        ? base.copyWith(color: AppColors.negative)
        : base;

    // Дерево вокруг TextField не должно меняться при фокусе: иначе поле
    // пересоздаётся и ввод уходит в никуда до повторного щелчка.
    return TextField(
      controller: _c,
      focusNode: _focus,
      textAlign: widget.align,
      style: style,
      maxLines: 1,
      cursorWidth: 1.5,
      inputFormatters: widget.numeric ? const [_AmountInput()] : null,
      onChanged: (_) {
        if (_invalid) setState(() => _invalid = false);
      },
      // Enter с неверной формулой оставляет поле открытым для исправления.
      onEditingComplete: () {},
      onSubmitted: (_) => _submit(),
      onTapOutside: (_) {
        if (_focus.hasFocus) _focus.unfocus();
      },
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        hintStyle: base.copyWith(color: AppColors.faint),
        filled: true,
        fillColor: focused ? AppColors.surface : Colors.transparent,
        hoverColor: AppColors.subtle,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: widget.dense ? 0 : 9,
        ),
        border: _border(Colors.transparent),
        enabledBorder: _border(Colors.transparent),
        focusedBorder: _border(
          _invalid ? AppColors.negative : AppColors.text,
          1.5,
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: isFormula && !focused && widget.showFormulaBadge
            ? Tooltip(
                message: 'Формула: ${widget.value}',
                child: Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text(
                    'ƒ',
                    style: TextStyle(
                      color: AppColors.faint,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  static OutlineInputBorder _border(Color c, [double w = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: c, width: w),
      );
}

/// В сумме — только цифры, пробелы, «,» и «.», знаки + − * / и скобки;
/// «=» — только первым символом. Недопустимая правка (буква, вставка
/// «1212=50+40») просто не принимается.
class _AmountInput extends TextInputFormatter {
  const _AmountInput();

  static final _allowed = RegExp(r'^=?[0-9+\-*/().,  ]*$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => _allowed.hasMatch(newValue.text) ? newValue : oldValue;
}

/// Ячейка с датой: по клику открывает календарь.
class DateCell extends StatelessWidget {
  const DateCell({
    super.key,
    required this.date,
    required this.onPick,
    this.format = fmtDate,
    this.hint = 'Дата',
    this.style,
  });

  final DateTime? date;
  final ValueChanged<DateTime> onPick;
  final String Function(DateTime) format;
  final String hint;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return _HoverBox(
      onTap: () async {
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          initialDate: date ?? now,
          firstDate: DateTime(1990),
          lastDate: DateTime(2100),
          locale: const Locale('ru'),
        );
        if (d != null) onPick(d);
      },
      child: Text(
        date == null ? hint : format(date!),
        style: (style ?? AppText.num).copyWith(
          color: date == null ? AppColors.faint : null,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Ячейка выбора из списка (Валюта, Статья).
class ChoiceCell extends StatelessWidget {
  const ChoiceCell({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.builder,
    this.allowCustom = false,
    this.customTitle = 'Своё значение',
  });

  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final Widget Function(String value)? builder;
  final bool allowCustom;
  final String customTitle;

  static const _custom = '\u0000custom';

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      onSelected: (v) async {
        if (v == _custom) {
          final text = await promptText(
            context,
            title: customTitle,
            initial: value,
          );
          if (text != null) onChanged(text);
        } else {
          onChanged(v);
        }
      },
      itemBuilder: (_) => [
        for (final o in options)
          PopupMenuItem(
            value: o,
            height: 38,
            child: Row(
              children: [
                Expanded(
                  child: builder != null
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: builder!(o),
                        )
                      : Text(o),
                ),
                if (o == value) const Icon(Icons.check_rounded, size: 16),
              ],
            ),
          ),
        if (allowCustom) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: _custom,
            height: 38,
            child: Text('Другое…'),
          ),
        ],
      ],
      child: _HoverBox(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: builder != null
                  ? builder!(value)
                  : Text(
                      value.isEmpty ? '—' : value,
                      style: AppText.body.copyWith(
                        color: value.isEmpty ? AppColors.faint : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 16, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}

class _HoverBox extends StatefulWidget {
  const _HoverBox({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_HoverBox> createState() => _HoverBoxState();
}

class _HoverBoxState extends State<_HoverBox> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: _hover ? AppColors.subtle : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: widget.child,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: widget.onTap == null
          ? box
          : GestureDetector(onTap: widget.onTap, child: box),
    );
  }
}

/// Диалог ввода строки.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String ok = 'Готово',
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: c,
          autofocus: true,
          style: AppText.body,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.text, width: 1.5),
            ),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        AppButton(label: 'Отмена', onPressed: () => Navigator.pop(ctx)),
        AppButton.primary(
          label: ok,
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
        ),
      ],
    ),
  );
}

/// Поле поиска из референса.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Поиск...',
    this.width = 320,
  });
  final ValueChanged<String> onChanged;
  final String hint;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 40,
      child: TextField(
        onChanged: onChanged,
        style: AppText.body,
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppText.muted,
          isDense: true,
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: AppColors.muted,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.text, width: 1.5),
          ),
        ),
      ),
    );
  }
}

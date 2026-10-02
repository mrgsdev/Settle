import 'package:flutter/material.dart';

import '../theme.dart';

/// Поле ввода с подписью в стиле приложения.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.obscure = false,
    this.lines = 1,
    this.style,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final bool obscure;
  final int lines;
  final TextStyle? style;
  final Widget? suffix;
  final VoidCallback? onChanged;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: c, width: w),
    );
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: obscure,
      minLines: lines,
      maxLines: lines,
      autocorrect: false,
      enableSuggestions: false,
      style: style ?? AppText.body,
      onChanged: (_) => onChanged?.call(),
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppText.muted,
        floatingLabelStyle: AppText.small.copyWith(color: AppColors.text),
        alignLabelWithHint: true,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        enabledBorder: border(AppColors.border),
        focusedBorder: border(AppColors.text, 1.5),
        suffixIcon: suffix,
      ),
    );
  }
}

/// Поле пароля с кнопкой «показать».
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final VoidCallback? onChanged;
  final VoidCallback? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: widget.controller,
      label: widget.label,
      autofocus: widget.autofocus,
      obscure: !_visible,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      suffix: IconButton(
        tooltip: _visible ? 'Скрыть' : 'Показать',
        icon: Icon(
          _visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 20,
          color: AppColors.muted,
        ),
        onPressed: () => setState(() => _visible = !_visible),
      ),
    );
  }
}

/// Флажок с подписью; нажимается и подпись.
class CheckRow extends StatelessWidget {
  const CheckRow({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Row(
          children: [
            Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
            const SizedBox(width: 4),
            Flexible(child: Text(label, style: AppText.body)),
          ],
        ),
      ),
    );
  }
}

/// Строка «подождите…» с индикатором либо текст ошибки.
class StatusLine extends StatelessWidget {
  const StatusLine({super.key, this.busy, this.error});

  /// Текст ожидания; если задан — показывается вместо ошибки.
  final String? busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (busy != null) {
      return Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(width: 10),
          Text(busy!, style: AppText.small),
        ],
      );
    }
    if (error != null) {
      return Text(
        error!,
        style: AppText.small.copyWith(color: AppColors.negative),
      );
    }
    return const SizedBox(height: 17);
  }
}

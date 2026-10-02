import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../excel/office_crypto.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/inputs.dart';

/// Вопрос перед экспортом: ставить ли пароль на файл.
/// Результат: null — отмена, '' — без пароля, иначе пароль.
class ExportOptionsDialog extends StatefulWidget {
  const ExportOptionsDialog({super.key});

  @override
  State<ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<ExportOptionsDialog> {
  final _password = TextEditingController();
  bool _protect = false;

  bool get _ready => !_protect || _password.text.isNotEmpty;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_ready) Navigator.pop(context, _protect ? _password.text : '');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Экспорт в Excel'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckRow(
              value: _protect,
              label: 'Поставить пароль на Excel-файл',
              onChanged: (v) => setState(() => _protect = v),
            ),
            if (_protect) ...[
              const SizedBox(height: 12),
              PasswordField(
                controller: _password,
                label: 'Пароль для файла',
                autofocus: true,
                onChanged: () => setState(() {}),
                onSubmitted: _submit,
              ),
              const SizedBox(height: 10),
              Text(
                'Excel и Settle спросят этот пароль при открытии файла. '
                'Без него файл не открыть.',
                style: AppText.small,
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        AppButton(label: 'Отмена', onPressed: () => Navigator.pop(context)),
        AppButton.primary(
          label: 'Экспортировать',
          onPressed: _ready ? _submit : null,
        ),
      ],
    );
  }
}

/// Пароль от книги Excel при импорте. Результат — расшифрованная книга
/// или null, если пользователь отменил.
class ExcelPasswordDialog extends StatefulWidget {
  const ExcelPasswordDialog({
    super.key,
    required this.fileName,
    required this.bytes,
  });

  final String fileName;
  final Uint8List bytes;

  @override
  State<ExcelPasswordDialog> createState() => _ExcelPasswordDialogState();
}

class _ExcelPasswordDialogState extends State<ExcelPasswordDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plain = await OfficeCrypto.decrypt(widget.bytes, _password.text);
      if (mounted) Navigator.pop(context, plain);
    } on WrongPasswordException {
      _error = 'Неверный пароль';
    } on OfficeCryptoException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Не удалось расшифровать файл: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Файл защищён паролем'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Введите пароль от «${widget.fileName}».',
              style: AppText.body,
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _password,
              label: 'Пароль',
              autofocus: true,
              onChanged: () {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: _open,
            ),
            const SizedBox(height: 10),
            StatusLine(busy: _busy ? 'Расшифровываем…' : null, error: _error),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        AppButton(
          label: 'Отмена',
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
        AppButton.primary(label: 'Открыть', onPressed: _busy ? null : _open),
      ],
    );
  }
}

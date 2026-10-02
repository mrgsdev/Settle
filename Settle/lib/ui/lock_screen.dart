import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';
import '../model/store.dart';
import '../security/vault.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/inputs.dart';

/// Экран перед открытием данных: создание пароля и кода восстановления
/// при первом запуске, вход по паролю и восстановление доступа по коду.
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.dataDir,
    required this.onUnlocked,
    this.kdf = PasswordKdf.standard,
  });

  final Directory dataDir;
  final ValueChanged<BudgetStore> onUnlocked;

  /// Сложность ключа из пароля для нового файла (в тестах — облегчённая).
  final PasswordKdf kdf;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

enum _Step {
  loading,
  createPassword,
  showCode,
  checkCode,
  unlock,
  enterRecovery,
  newPassword,
}

class _LockScreenState extends State<LockScreen> {
  _Step _step = _Step.loading;
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  final _recoveryInput = TextEditingController();
  final _codeCheck = TextEditingController();

  /// Новый код — показывается один раз.
  String _code = '';
  bool _codeSaved = false;

  /// Файл уже открыт, и ему выдаётся код вместо старой фразы из 12 слов.
  Vault? _upgrade;

  /// Открыто кодом (или фразой), ждём новый пароль.
  Vault? _recovered;

  /// Файл первых версий: доступ восстанавливается фразой из 12 слов.
  bool _usesPhrase = false;
  bool _busy = false;
  String? _error;

  File get _file => BudgetStore.vaultFile(widget.dataDir);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    var step = _Step.createPassword;
    if (await _file.exists()) {
      step = _Step.unlock;
      try {
        _usesPhrase = await Vault.usesPhrase(_file);
      } catch (_) {
        // Повреждённый файл — ошибка покажется при входе.
      }
    }
    if (mounted) _go(step);
  }

  @override
  void dispose() {
    for (final c in [_password, _repeat, _recoveryInput, _codeCheck]) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(_Step step) => setState(() {
    _step = step;
    _error = null;
  });

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  /// Долгое действие (ключ из пароля, шифрование) с индикатором и ошибкой.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on WrongSecretException {
      _fail(switch (_step) {
        _Step.unlock => 'Неверный пароль',
        _ when _usesPhrase => 'Эта фраза не подходит к сохранённым данным',
        _ => 'Неверный код восстановления',
      });
    } on VaultFormatException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Не удалось открыть данные: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Файл открыт: старой фразе выдаём замену, иначе — в приложение.
  Future<void> _opened(Vault vault) async {
    if (vault.hasLegacyRecovery) return _startCode(upgrade: vault);
    _finish(await BudgetStore.open(vault));
  }

  void _finish(BudgetStore store) {
    for (final c in [_password, _repeat, _recoveryInput, _codeCheck]) {
      c.clear();
    }
    _code = '';
    _upgrade = _recovered = null;
    widget.onUnlocked(store);
  }

  String? _passwordError() {
    if (_password.text.length < 6) {
      return 'Пароль должен быть не короче 6 символов';
    }
    if (_password.text != _repeat.text) return 'Пароли не совпадают';
    return null;
  }

  // ───────────────────────────── Действия ─────────────────────────────

  void _createPassword() {
    final error = _passwordError();
    if (error != null) return _fail(error);
    _startCode();
  }

  void _startCode({Vault? upgrade}) {
    _code = Vault.newRecoveryCode();
    _codeSaved = false;
    _codeCheck.clear();
    _upgrade = upgrade;
    _go(_Step.showCode);
  }

  void _checkCode() {
    if (Vault.normalizeCode(_codeCheck.text) != _code) {
      return _fail('Код не совпадает — посмотрите его ещё раз');
    }
    _run(() async {
      final upgrade = _upgrade;
      if (upgrade != null) {
        await upgrade.setRecoveryCode(_code);
        _finish(await BudgetStore.open(upgrade));
      } else {
        _finish(
          await BudgetStore.create(
            widget.dataDir,
            password: _password.text,
            recoveryCode: _code,
            kdf: widget.kdf,
          ),
        );
      }
    });
  }

  void _unlock() =>
      _run(() async => _opened(await Vault.unlock(_file, _password.text)));

  void _enterRecovery() {
    final input = _recoveryInput.text;
    final error = _usesPhrase
        ? Vault.phraseError(input)
        : Vault.codeError(input);
    if (error != null) return _fail(error);
    _run(() async {
      _recovered = await Vault.recover(_file, input);
      _password.clear();
      _repeat.clear();
      _go(_Step.newPassword);
    });
  }

  void _newPassword() {
    final error = _passwordError();
    if (error != null) return _fail(error);
    _run(() async {
      final vault = _recovered!;
      await vault.changePassword(_password.text);
      await _opened(vault);
    });
  }

  // ───────────────────────────── Экраны ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _step == _Step.showCode ? 520 : 400,
            ),
            child: _step == _Step.loading
                ? const SizedBox()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          AppLogo(size: 40),
                          SizedBox(width: 12),
                          Text('Settle', style: AppText.appTitle),
                        ],
                      ),
                      const SizedBox(height: 36),
                      ..._content(),
                      const SizedBox(height: 40),
                      Center(
                        child: Text(
                          'Версия $appVersion',
                          style: AppText.small.copyWith(color: AppColors.faint),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content() => switch (_step) {
    _Step.loading => const [],
    _Step.createPassword => [
      ..._heading(
        'Придумайте пароль',
        'Он понадобится при каждом запуске. Данные хранятся только '
            'на этом компьютере и зашифрованы этим паролем.',
      ),
      PasswordField(
        controller: _password,
        label: 'Пароль',
        autofocus: true,
        onChanged: _clearError,
      ),
      const SizedBox(height: 12),
      PasswordField(
        controller: _repeat,
        label: 'Повторите пароль',
        onChanged: _clearError,
        onSubmitted: _createPassword,
      ),
      ..._status(),
      AppButton.primary(label: 'Продолжить', onPressed: _createPassword),
    ],
    _Step.showCode => [
      ..._heading(
        _upgrade == null ? 'Код восстановления' : 'Новый код восстановления',
        _upgrade == null
            ? 'Если вы забудете пароль, войти можно будет только с этим '
                  'кодом. Запишите его и храните в надёжном месте.'
            : 'Вместо фразы из 12 слов теперь короткий код. Запишите его — '
                  'старая фраза после этого перестанет работать.',
      ),
      _CodeView(_code),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: Text(
              'Заглавные и строчные буквы различаются.',
              style: AppText.small,
            ),
          ),
          AppButton(
            icon: Icons.copy_rounded,
            label: 'Скопировать',
            dense: true,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _code));
              showSnack(context, 'Код скопирован');
            },
          ),
        ],
      ),
      const SizedBox(height: 20),
      const _Warning(
        'Без пароля и без кода восстановить данные невозможно — '
        'их не знает никто, кроме вас.',
      ),
      const SizedBox(height: 16),
      CheckRow(
        value: _codeSaved,
        label: 'Я записал(а) код',
        onChanged: (v) => setState(() => _codeSaved = v),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          if (_upgrade == null) ...[
            AppButton(
              label: 'Назад',
              onPressed: () => _go(_Step.createPassword),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: AppButton.primary(
              label: 'Далее',
              onPressed: _codeSaved ? () => _go(_Step.checkCode) : null,
            ),
          ),
        ],
      ),
    ],
    _Step.checkCode => [
      ..._heading(
        'Проверка кода',
        'Введите код восстановления, чтобы убедиться, что он записан верно.',
      ),
      AppTextField(
        controller: _codeCheck,
        label: 'Код восстановления',
        autofocus: true,
        style: _codeInputStyle,
        onChanged: _clearError,
        onSubmitted: _checkCode,
      ),
      ..._status(),
      Row(
        children: [
          AppButton(
            label: 'Показать код',
            onPressed: _busy ? null : () => _go(_Step.showCode),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AppButton.primary(
              label: 'Готово',
              onPressed: _busy ? null : _checkCode,
            ),
          ),
        ],
      ),
    ],
    _Step.unlock => [
      ..._heading('Вход', 'Введите пароль, чтобы открыть данные.'),
      PasswordField(
        controller: _password,
        label: 'Пароль',
        autofocus: true,
        onChanged: _clearError,
        onSubmitted: _unlock,
      ),
      ..._status(),
      AppButton.primary(label: 'Войти', onPressed: _busy ? null : _unlock),
      const SizedBox(height: 12),
      Center(
        child: AppButton.ghost(
          label: 'Забыли пароль?',
          onPressed: _busy
              ? null
              : () {
                  _recoveryInput.clear();
                  _go(_Step.enterRecovery);
                },
        ),
      ),
    ],
    _Step.enterRecovery => [
      ..._heading(
        'Восстановление доступа',
        _usesPhrase
            ? 'Введите 12 слов фразы восстановления через пробел — '
                  'в том же порядке, в каком они записаны.'
            : 'Введите код восстановления — 10 латинских букв. '
                  'Заглавные и строчные буквы различаются.',
      ),
      AppTextField(
        controller: _recoveryInput,
        label: _usesPhrase ? 'Фраза восстановления' : 'Код восстановления',
        autofocus: true,
        lines: _usesPhrase ? 3 : 1,
        style: _usesPhrase ? null : _codeInputStyle,
        onChanged: _clearError,
        onSubmitted: _usesPhrase ? null : _enterRecovery,
      ),
      ..._status(),
      AppButton.primary(
        label: 'Продолжить',
        onPressed: _busy ? null : _enterRecovery,
      ),
      const SizedBox(height: 12),
      Center(
        child: AppButton.ghost(
          label: 'Вспомнили пароль? Войти',
          onPressed: _busy
              ? null
              : () {
                  _password.clear();
                  _go(_Step.unlock);
                },
        ),
      ),
    ],
    _Step.newPassword => [
      ..._heading(
        'Новый пароль',
        _usesPhrase
            ? 'Фраза подошла. Придумайте новый пароль — затем вместо фразы '
                  'вы получите код восстановления.'
            : 'Код подошёл. Придумайте новый пароль — код восстановления '
                  'останется прежним.',
      ),
      PasswordField(
        controller: _password,
        label: 'Новый пароль',
        autofocus: true,
        onChanged: _clearError,
      ),
      const SizedBox(height: 12),
      PasswordField(
        controller: _repeat,
        label: 'Повторите пароль',
        onChanged: _clearError,
        onSubmitted: _newPassword,
      ),
      ..._status(),
      AppButton.primary(
        label: 'Сохранить и войти',
        onPressed: _busy ? null : _newPassword,
      ),
    ],
  };

  static TextStyle get _codeInputStyle => TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    letterSpacing: 2,
    color: AppColors.text,
  );

  List<Widget> _heading(String title, String text) => [
    Text(title, style: AppText.pageTitle.copyWith(fontSize: 24)),
    const SizedBox(height: 8),
    Text(text, style: AppText.muted),
    const SizedBox(height: 24),
  ];

  /// Ошибка или «подождите» между полями и кнопкой.
  List<Widget> _status() => [
    const SizedBox(height: 12),
    StatusLine(
      busy: _busy
          ? switch (_step) {
              _Step.unlock => 'Проверяем пароль…',
              _Step.enterRecovery =>
                _usesPhrase ? 'Проверяем фразу…' : 'Проверяем код…',
              _Step.newPassword => 'Сохраняем пароль…',
              _ when _upgrade != null => 'Сохраняем код…',
              _ => 'Шифруем данные…',
            }
          : null,
      error: _error,
    ),
    const SizedBox(height: 16),
  ];
}

/// Код восстановления по буквам: две группы по пять.
class _CodeView extends StatelessWidget {
  const _CodeView(this.code);
  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.subtle,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (var i = 0; i < code.length; i++) ...[
            if (i > 0) SizedBox(width: i == code.length ~/ 2 ? 16 : 6),
            Expanded(
              child: Container(
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.raised,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  code[i],
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.consumption.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: AppColors.consumptionInk,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppText.body.copyWith(color: AppColors.consumptionInk),
            ),
          ),
        ],
      ),
    );
  }
}

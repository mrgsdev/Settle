import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../security/vault.dart';
import 'budget.dart';
import 'calc.dart';

/// Хранилище данных: держит книгу в памяти, сохраняет её в зашифрованный файл
/// (автоматически, с небольшой задержкой) и даёт операции над листами.
class BudgetStore extends ChangeNotifier {
  BudgetStore._(this._vault, this.data);

  final Vault? _vault;
  BudgetData data;

  /// Увеличивается при полной замене данных (импорт, сброс) — чтобы поля ввода
  /// пересоздались с новыми значениями.
  int revision = 0;

  BudgetData? _undo;
  String? _undoLabel;
  Timer? _saveTimer;
  DateTime? lastSaved;
  String? saveError;

  String? get dataPath => _vault?.file.path;
  bool get canUndo => _undo != null;
  String? get undoLabel => _undoLabel;

  /// Хранилище без файла — для тестов и предпросмотра.
  factory BudgetStore.memory(BudgetData data) => BudgetStore._(null, data);

  /// Данные из открытого паролем (или фразой) файла.
  static Future<BudgetStore> open(Vault vault) async {
    final json = jsonDecode(await vault.read()) as Map<String, dynamic>;
    return BudgetStore._(vault, BudgetData.fromJson(json));
  }

  /// Первый запуск: файл с паролем и кодом восстановления. Данные прежней
  /// версии без пароля (budget.json) переносятся в него, а открытый файл
  /// удаляется; если их нет — начинаем с пустого шаблона.
  static Future<BudgetStore> create(
    Directory dir, {
    required String password,
    required String recoveryCode,
    PasswordKdf kdf = PasswordKdf.standard,
  }) async {
    final legacy = await _legacyData(dir);
    final data = legacy?.$1 ?? BudgetData.template();
    final vault = await Vault.create(
      vaultFile(dir),
      password: password,
      recoveryCode: recoveryCode,
      data: jsonEncode(data.toJson()),
      kdf: kdf,
    );
    if (legacy != null) {
      for (final f in [legacy.$2, File('${legacy.$2.path}.tmp')]) {
        try {
          if (await f.exists()) await f.delete();
        } catch (e) {
          debugPrint('Не удалось удалить $f: $e');
        }
      }
    }
    return BudgetStore._(vault, data);
  }

  static File vaultFile(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}settle.vault');

  /// Папка с данными. Портативная версия (Windows): если рядом с exe лежит
  /// portable.txt, данные хранятся в UserData рядом с программой — например,
  /// на флешке. Иначе — в папке приложения в профиле пользователя.
  static Future<Directory> dataDirectory() async {
    if (Platform.isWindows) {
      final sep = Platform.pathSeparator;
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      if (File('$exeDir${sep}portable.txt').existsSync()) {
        return Directory('$exeDir${sep}UserData');
      }
    }
    return getApplicationSupportDirectory();
  }

  /// budget.json прежних версий (без пароля): в папке данных, а на Windows ещё
  /// и в соседней папке под старым названием приложения («Кагиз Трахи»).
  static Future<(BudgetData, File)?> _legacyData(Directory dir) async {
    final sep = Platform.pathSeparator;
    final files = [
      File('${dir.path}${sep}budget.json'),
      if (Platform.isWindows)
        File([dir.parent.path, 'Кагиз Трахи', 'budget.json'].join(sep)),
    ];
    for (final f in files) {
      if (!await f.exists()) continue;
      try {
        final json = jsonDecode(await f.readAsString());
        return (BudgetData.fromJson(json as Map<String, dynamic>), f);
      } catch (e) {
        debugPrint('Не удалось прочитать $f: $e');
      }
    }
    return null;
  }

  /// Точечное изменение данных.
  void edit(void Function(BudgetData d) change) {
    change(data);
    _changed();
  }

  /// Изменение с возможностью отмены одним действием.
  void editUndoable(String label, void Function(BudgetData d) change) {
    _undo = data.clone();
    _undoLabel = label;
    change(data);
    revision++;
    _changed();
  }

  void replace(BudgetData next, {required String label}) {
    _undo = data;
    _undoLabel = label;
    data = next;
    revision++;
    _changed();
  }

  void undo() {
    final prev = _undo;
    if (prev == null) return;
    data = prev;
    _undo = null;
    _undoLabel = null;
    revision++;
    _changed();
  }

  void _changed() {
    notifyListeners();
    if (_vault == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), save);
  }

  Future<void> save() async {
    final vault = _vault;
    if (vault == null) return;
    try {
      await vault.write(jsonEncode(data.toJson()));
      lastSaved = DateTime.now();
      saveError = null;
    } catch (e) {
      saveError = '$e';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  // ───────────────────────────── Баланс ─────────────────────────────

  /// Новый блок месяца: следующий за последним, с теми же источниками и пустыми балансами.
  void addBalanceMonth() => edit((d) {
    final last = d.months.isEmpty ? null : d.months.last;
    final now = DateTime.now();
    final date = last == null
        ? DateTime(now.year, now.month, 1)
        : DateTime(last.date.year, last.date.month + 1, 1);
    d.months.add(
      BalanceMonth(
        title: BalanceMonth.defaultTitle(date),
        date: date,
        sources: last == null
            ? [BalanceSource()]
            : [for (final s in last.sources) s.copyEmpty()],
      ),
    );
  });

  /// Заполнить «Статья · Сумма» суммами балансов месяца по статьям.
  void fillSharesFrom(BalanceMonth m) => edit((d) {
    for (final row in d.shares) {
      final key = _articleKey(row.label);
      if (key == null) continue;
      final total = m.sources
          .where((s) => _articleKey(s.article) == key)
          .fold<double>(0, (sum, s) => sum + Raw.num(s.balance));
      row.amount = Raw.formatNumber(total);
    }
  });

  static String? _articleKey(String label) {
    final l = label.trim().toLowerCase();
    if (l.startsWith('потреб')) return 'c';
    if (l.startsWith('инвест')) return 'i';
    if (l.startsWith('сбереж')) return 's';
    return l.isEmpty ? null : l;
  }

  // ───────────────────────────── Расходы ─────────────────────────────

  /// Переход к следующему месяцу на листе «Расходы».
  void nextExpenseMonth({
    required bool writeToDynamics,
    required bool carryRemainder,
  }) {
    editUndoable('Переход к следующему месяцу', (d) {
      final e = d.expenses;
      if (writeToDynamics) {
        final total = e.total.number ?? 0;
        var year = d.dynamics.years.where((y) => y.year == e.year).firstOrNull;
        if (year == null) {
          year = DynamicsYear(year: e.year);
          d.dynamics.years
            ..add(year)
            ..sort((a, b) => a.year.compareTo(b.year));
        }
        year.values[e.month - 1] = Raw.formatNumber(total);
      }
      final next = DateTime(e.year, e.month + 1, 1);
      final rest = e.remainder.number;
      d.expenses = ExpenseSheet(
        monthTitle: monthTitle(next.year, next.month),
        year: next.year,
        month: next.month,
        days: ExpenseSheet.generateDays(next.year, next.month),
        prevRemainder: carryRemainder && rest != null
            ? Raw.formatNumber(rest)
            : '',
        budget: e.budget,
        mandatoryTitle: e.mandatoryTitle,
        mandatory: [
          for (final m in e.mandatory)
            MandatoryItem(name: m.name, plan: m.plan),
        ],
      );
    });
  }

  // ───────────────────────────── Динамика ─────────────────────────────

  void addDynamicsYear() => edit((d) {
    final years = d.dynamics.years;
    final next = years.isEmpty
        ? DateTime.now().year
        : years.map((y) => y.year).reduce((a, b) => a > b ? a : b) + 1;
    years.add(DynamicsYear(year: next));
  });
}

/// Доступ к хранилищу из дерева виджетов; перестраивает зависимых при изменениях.
/// До ввода пароля хранилища нет (`store == null`).
class StoreScope extends InheritedNotifier<BudgetStore> {
  const StoreScope({
    super.key,
    required BudgetStore? store,
    required super.child,
  }) : super(notifier: store);

  static BudgetStore of(BuildContext context) => maybeOf(context)!;

  static BudgetStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()?.notifier;

  static BudgetStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}

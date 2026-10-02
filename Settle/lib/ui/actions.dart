import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../excel/budget_excel.dart';
import '../excel/office_crypto.dart';
import '../excel/xlsx_reader.dart';
import '../model/budget.dart';
import '../model/store.dart';
import 'excel_dialogs.dart';
import 'format.dart';
import 'widgets/common.dart';

const _xlsx = XTypeGroup(
  label: 'Книга Excel',
  extensions: ['xlsx'],
  uniformTypeIdentifiers: ['org.openxmlformats.spreadsheetml.sheet'],
);

String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;

/// Экспорт всей книги в .xlsx того же формата, что и «Бюджет.xlsx»,
/// по желанию — с паролем на файл.
Future<void> exportExcel(BuildContext context, {String? suggestedName}) async {
  final store = StoreScope.read(context);
  final e = store.data.expenses;
  final password = await showDialog<String>(
    context: context,
    builder: (_) => const ExportOptionsDialog(),
  );
  if (password == null || !context.mounted) return;
  final location = await getSaveLocation(
    suggestedName: suggestedName ?? 'Бюджет.xlsx',
    acceptedTypeGroups: const [_xlsx],
    confirmButtonText: 'Сохранить',
  );
  if (location == null) return;
  var path = location.path;
  if (!path.toLowerCase().endsWith('.xlsx')) path = '$path.xlsx';
  try {
    var bytes = BudgetExcel.export(store.data);
    if (password.isNotEmpty) {
      bytes = await OfficeCrypto.encrypt(bytes, password);
    }
    await File(path).writeAsBytes(bytes, flush: true);
    if (!context.mounted) return;
    showSnack(
      context,
      '${password.isEmpty ? 'Сохранено' : 'Сохранено с паролем'}: '
      '${_baseName(path)} · ${monthYear(e.year, e.month)}',
      action: 'Показать',
      onAction: () => revealInFiles(path),
    );
  } catch (err) {
    if (context.mounted) showSnack(context, 'Не удалось сохранить файл: $err');
  }
}

/// Импорт книги .xlsx: заменяет текущие данные (с возможностью отмены).
/// Книга с паролем открывается после ввода пароля.
Future<void> importExcel(BuildContext context) async {
  final store = StoreScope.read(context);
  final file = await openFile(
    acceptedTypeGroups: const [_xlsx],
    confirmButtonText: 'Открыть',
  );
  if (file == null || !context.mounted) return;
  try {
    var bytes = await file.readAsBytes();
    if (OfficeCrypto.isEncrypted(bytes)) {
      if (!context.mounted) return;
      final plain = await showDialog<Uint8List>(
        context: context,
        builder: (_) => ExcelPasswordDialog(fileName: file.name, bytes: bytes),
      );
      if (plain == null || !context.mounted) return;
      bytes = plain;
    }
    final result = BudgetExcel.import(bytes);
    if (!context.mounted) return;
    final d = result.data;
    final years = d.dynamics.years.map((y) => y.year).join(', ');
    final summary = [
      'Баланс: ${d.months.length} ${plural(d.months.length, 'месяц', 'месяца', 'месяцев')}',
      'Расходы: ${monthYear(d.expenses.year, d.expenses.month)}',
      if (years.isNotEmpty) 'Динамика: $years',
      'Долги: ${d.debts.length} ${plural(d.debts.length, 'запись', 'записи', 'записей')}',
    ].join('\n');
    final warn = result.warnings.isEmpty
        ? ''
        : '\n\nВнимание:\n${result.warnings.map((w) => '• $w').join('\n')}';
    final ok = await confirm(
      context,
      title: 'Импорт из Excel',
      text:
          'Заменить текущие данные содержимым «${file.name}»?\n\n$summary$warn\n\nВернуть прежние данные можно кнопкой «Отменить».',
      ok: 'Импортировать',
    );
    if (!ok || !context.mounted) return;
    store.replace(d, label: 'Импорт');
    showUndoSnack(context, 'Данные загружены из «${file.name}»');
  } on XlsxFormatException catch (err) {
    if (context.mounted) showSnack(context, err.message);
  } catch (err) {
    if (context.mounted) showSnack(context, 'Не удалось прочитать файл: $err');
  }
}

Future<void> resetToTemplate(BuildContext context) async {
  final store = StoreScope.read(context);
  final ok = await confirm(
    context,
    title: 'Начать с шаблона?',
    text:
        'Все листы будут заменены пустым шаблоном на текущий месяц. Текущие данные можно вернуть кнопкой «Отменить».',
    ok: 'Сбросить',
  );
  if (!ok || !context.mounted) return;
  store.replace(BudgetData.template(), label: 'Сброс');
  showUndoSnack(context, 'Данные сброшены к шаблону');
}

/// Открыть ссылку в браузере по умолчанию.
Future<void> openUrl(String url) async {
  try {
    if (Platform.isWindows) {
      await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else {
      await Process.run('xdg-open', [url]);
    }
  } catch (_) {}
}

/// Показать файл в Finder / Проводнике.
Future<void> revealInFiles(String path) async {
  try {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
    } else {
      await Process.run('xdg-open', [File(path).parent.path]);
    }
  } catch (_) {}
}

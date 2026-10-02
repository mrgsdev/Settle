import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settle/excel/budget_excel.dart';
import 'package:settle/excel/office_crypto.dart';
import 'package:settle/ui/excel_dialogs.dart';
import 'package:settle/ui/theme.dart';

import 'demo_data.dart';
import 'test_fonts.dart';

void main() {
  final shots = Platform.environment['KT_SHOTS'];
  final key = GlobalKey();

  Future<void> shot(WidgetTester tester, String name) async {
    if (shots == null) return;
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$shots/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  /// Открыть диалог поверх пустого окна; результат — в [result].
  Future<void> open<T>(
    WidgetTester tester,
    Widget dialog,
    void Function(T?) result,
  ) async {
    await tester.runAsync(loadTestFonts);
    tester.view.physicalSize = const Size(900, 600) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async => result(
                    await showDialog<T>(
                      context: context,
                      builder: (_) => dialog,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('экспорт: без пароля и с паролем', (tester) async {
    String? result = 'не закрыт';
    await open<String>(tester, const ExportOptionsDialog(), (r) => result = r);
    await shot(tester, 'excel_1_export');
    await tester.tap(find.text('Экспортировать'));
    await tester.pumpAndSettle();
    expect(result, '');

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Поставить пароль на Excel-файл'));
    await tester.pumpAndSettle();
    // Пока пароль пуст, «Экспортировать» не работает.
    await tester.tap(find.text('Экспортировать'));
    await tester.pumpAndSettle();
    expect(find.text('Пароль для файла'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'любой пароль');
    await tester.pump();
    await shot(tester, 'excel_2_export_password');
    await tester.tap(find.text('Экспортировать'));
    await tester.pumpAndSettle();
    expect(result, 'любой пароль');
  });

  testWidgets('импорт книги с паролем', (tester) async {
    final xlsx = BudgetExcel.export(demoData());
    final locked = (await tester.runAsync(
      () => OfficeCrypto.encrypt(xlsx, 'секрет', spinCount: 1000),
    ))!;
    Uint8List? result;
    await open<Uint8List>(
      tester,
      ExcelPasswordDialog(fileName: 'Бюджет.xlsx', bytes: locked),
      (r) => result = r,
    );
    expect(find.text('Введите пароль от «Бюджет.xlsx».'), findsOneWidget);

    Future<void> submit(String password) async {
      await tester.enterText(find.byType(TextField), password);
      await tester.tap(find.text('Открыть'));
      for (var i = 0; i < 200; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('Расшифровываем…').evaluate().isEmpty) break;
      }
      await tester.pumpAndSettle();
    }

    await submit('Секрет');
    expect(find.text('Неверный пароль'), findsOneWidget);
    await shot(tester, 'excel_3_import_wrong');
    await submit('секрет');
    expect(find.byType(AlertDialog), findsNothing);
    expect(result, xlsx);
  });
}

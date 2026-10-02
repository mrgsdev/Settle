import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settle/app_info.dart';
import 'package:settle/main.dart';
import 'package:settle/model/store.dart';
import 'package:settle/ui/theme.dart';

import 'demo_data.dart';
import 'test_fonts.dart';

void main() {
  test('версия совпадает с pubspec.yaml', () {
    final line = File(
      'pubspec.yaml',
    ).readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line, startsWith('version: $appVersion+'));
  });

  final shots = Platform.environment['KT_SHOTS'];
  final key = GlobalKey();
  tearDown(() => AppColors.palette = AppPalette.light);

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

  Future<void> openMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('Ещё'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  testWidgets('тёмная тема и «О программе»', (tester) async {
    await tester.runAsync(loadTestFonts);
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: SettleApp(store: BudgetStore.memory(demoData())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Баланс').first);
    await tester.pumpAndSettle();
    Color bg() => Theme.of(
      tester.element(find.byType(Scaffold).first),
    ).scaffoldBackgroundColor;
    Color titleColor() =>
        tester.widget<Text>(find.text('Settle').first).style!.color!;
    expect(bg(), AppPalette.light.bg);
    expect(titleColor(), AppPalette.light.text);

    await openMenu(tester, 'Оформление…');
    await tester.tap(find.text('Тёмная'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isTrue);
    expect(bg(), AppPalette.darkPalette.bg);
    // Виджеты перестроены с новыми цветами, вкладка не сбросилась.
    expect(titleColor(), AppPalette.darkPalette.text);
    expect(find.text('Новый месяц'), findsOneWidget);
    await shot(tester, 'dark_balance');
    for (final tab in ['Обзор', 'Расходы', 'Долги']) {
      await tester.tap(find.text(tab).first);
      await shot(tester, 'dark_$tab');
    }

    await openMenu(tester, 'О программе');
    expect(find.text('Версия $appVersion'), findsOneWidget);
    expect(find.text(developerName), findsOneWidget);
    await shot(tester, 'dark_about');
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();

    await openMenu(tester, 'Оформление…');
    await tester.tap(find.text('Светлая'));
    await tester.pumpAndSettle();
    expect(bg(), AppPalette.light.bg);
    expect(tester.takeException(), isNull);
  });
}

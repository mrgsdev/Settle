import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settle/main.dart';
import 'package:settle/model/store.dart';

import 'demo_data.dart';
import 'test_fonts.dart';

void main() {
  final out = Platform.environment['KT_SHOTS'];

  testWidgets('скриншоты всех вкладок', (tester) async {
    await tester.runAsync(loadTestFonts);
    tester.view.physicalSize =
        Size(1440, double.parse(Platform.environment['KT_H'] ?? '1000')) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final store = BudgetStore.memory(demoData());
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: SettleApp(store: store),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      if (out == null) return;
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    await shot('1_overview');
    for (final (i, tab) in [
      (2, 'Баланс'),
      (3, 'Расходы'),
      (4, 'Динамика'),
      (5, 'Долги'),
    ]) {
      await tester.tap(find.text(tab).first);
      await shot('${i}_$tab');
    }
    expect(tester.takeException(), isNull);
  });
}

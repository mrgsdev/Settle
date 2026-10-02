import 'dart:io';

import 'package:flutter/services.dart';

Future<ByteData> _font(String path) => Future.value(
  ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer),
);

/// Настоящие шрифты в тестах (по умолчанию flutter_test рисует квадратами Ahem).
Future<void> loadTestFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(_font('assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      '/Volumes/T7/Developer/Flutter/flutter';
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      _font(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    );
  await icons.load();
}

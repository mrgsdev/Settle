import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:settle/excel/budget_excel.dart';
import 'package:settle/excel/cfb.dart';
import 'package:settle/excel/office_crypto.dart';

import 'demo_data.dart';

void main() {
  test('составной файл OLE: запись → чтение', () {
    final rnd = Random(1);
    Uint8List blob(int n) =>
        Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
    final streams = {
      'Small': blob(100),
      'Exact4096': blob(4096),
      'Big': blob(70000),
      'Empty': Uint8List(0),
      '\u0006DataSpaces/Version': blob(76),
      '\u0006DataSpaces/TransformInfo/StrongEncryptionTransform/\u0006Primary':
          blob(200),
    };
    final back = Cfb.read(Cfb.write(streams));
    expect(back.keys.toSet(), streams.keys.toSet());
    for (final MapEntry(:key, :value) in streams.entries) {
      expect(back[key], value, reason: key);
    }
  });

  test('книга с паролем: шифрование → расшифровка → импорт', () async {
    final xlsx = BudgetExcel.export(demoData());
    expect(OfficeCrypto.isEncrypted(xlsx), isFalse);

    final protected = await OfficeCrypto.encrypt(xlsx, 'Пароль 123');
    expect(OfficeCrypto.isEncrypted(protected), isTrue);
    final out = Platform.environment['KT_OUT'];
    if (out != null) File('$out/protected.xlsx').writeAsBytesSync(protected);

    await expectLater(
      OfficeCrypto.decrypt(protected, 'пароль 123'),
      throwsA(isA<WrongPasswordException>()),
    );
    final plain = await OfficeCrypto.decrypt(protected, 'Пароль 123');
    expect(plain, xlsx);
    final data = BudgetExcel.import(plain).data;
    expect(data.months.map((m) => m.title), [
      'Июль 2026',
      'Август 2026',
      'Сентябрь 2026',
    ]);
  });

  // Книга, запароленная самим Excel: KT_XLSX_LOCKED=путь, KT_XLSX_PASSWORD=пароль.
  final locked = Platform.environment['KT_XLSX_LOCKED'];
  test('книга, запароленная в Excel', () async {
    final bytes = File(locked!).readAsBytesSync();
    expect(OfficeCrypto.isEncrypted(bytes), isTrue);
    await expectLater(
      OfficeCrypto.decrypt(bytes, 'не тот'),
      throwsA(isA<WrongPasswordException>()),
    );
    final plain = await OfficeCrypto.decrypt(
      bytes,
      Platform.environment['KT_XLSX_PASSWORD']!,
    );
    final r = BudgetExcel.import(plain);
    expect(r.data.months, isNotEmpty);
    expect(r.data.months.first.title, isNot(isEmpty));
    // ignore: avoid_print
    print(
      'Excel → ${r.data.months.map((m) => m.title).join(', ')}; '
      'долги: ${r.data.debts.length}',
    );
  }, skip: locked == null);
}

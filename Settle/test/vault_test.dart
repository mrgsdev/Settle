import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:settle/model/budget.dart';
import 'package:settle/model/store.dart';
import 'package:settle/security/vault.dart';

import 'vault_helpers.dart';

void main() {
  late Directory dir;
  late File file;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('settle_test_');
    file = BudgetStore.vaultFile(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('пароль, код восстановления и смена пароля', () async {
    final code = Vault.newRecoveryCode();
    expect(code, matches(RegExp(r'^[A-Za-z]{10}$')));
    expect(Vault.codeError(code), isNull);

    await Vault.create(
      file,
      password: 'secret1',
      recoveryCode: code,
      data: '{"note":"зарплата"}',
      kdf: fastKdf,
    );
    // В файле нет открытых данных и самого кода.
    final raw = file.readAsStringSync();
    expect(raw, isNot(contains('note')));
    expect(raw, isNot(contains(code)));
    expect(await Vault.usesPhrase(file), isFalse);

    await expectLater(
      Vault.unlock(file, 'secret2'),
      throwsA(isA<WrongSecretException>()),
    );
    final vault = await Vault.unlock(file, 'secret1');
    expect(vault.hasLegacyRecovery, isFalse);
    expect(await vault.read(), '{"note":"зарплата"}');
    await vault.write('{"note":"аванс"}');

    // Пробелы и дефисы не важны.
    final spaced = '${code.substring(0, 5)} - ${code.substring(5)}';
    final recovered = await Vault.recover(file, spaced);
    expect(await recovered.read(), '{"note":"аванс"}');
    await recovered.changePassword('newpass');

    await expectLater(
      Vault.unlock(file, 'secret1'),
      throwsA(isA<WrongSecretException>()),
    );
    expect(
      await (await Vault.unlock(file, 'newpass')).read(),
      '{"note":"аванс"}',
    );
    // Код после смены пароля прежний; чужой код не подходит.
    expect(await (await Vault.recover(file, code)).read(), '{"note":"аванс"}');
    await expectLater(
      Vault.recover(file, Vault.newRecoveryCode()),
      throwsA(isA<WrongSecretException>()),
    );
  });

  test('проверка и нормализация кода', () {
    // Похожих при записи от руки букв в коде нет.
    for (var i = 0; i < 200; i++) {
      expect(
        Vault.newRecoveryCode(),
        isNot(matches(RegExp('[IOilocjkpsuvwxz]'))),
      );
    }
    expect(Vault.normalizeCode(' KWJbh-fKQJW '), 'KWJbhfKQJW');
    // k, s, w бывают только заглавными — регистр исправляется сам.
    expect(Vault.normalizeCode('kwjbhfkQjw'), 'KWJbhfKQJW');
    // У b, h, f, q строчная и заглавная различаются — их регистр сохраняется.
    expect(Vault.normalizeCode('KWJBHFKqJW'), 'KWJBHFKqJW');
    expect(Vault.codeError('KWJbhfKQJW'), isNull);
    expect(Vault.codeError('KWJbhfKQJ'), 'В коде 10 букв, сейчас 9');
    expect(Vault.codeError('KWJbhfKQJ0'), 'В коде нет символов: 0');
    expect(Vault.codeError('KWJbhfKQJi'), 'В коде нет символов: i');
  });

  test('проверка введённой фразы (старые файлы)', () {
    expect(Vault.phraseError(validPhrase), isNull);
    expect(
      Vault.phraseError(validPhrase.split(' ').skip(1).join(' ')),
      'Нужно 12 слов, сейчас 11',
    );
    expect(
      Vault.phraseError(validPhrase.replaceFirst('about', 'привет')),
      contains('привет'),
    );
    expect(Vault.phraseError(badChecksum), contains('ошибкой'));
  });

  test(
    'старый файл с фразой: вход, восстановление, замена фразы кодом',
    () async {
      await writeLegacyVault(
        file,
        password: 'secret1',
        phrase: validPhrase,
        data: '{"note":"старое"}',
      );
      expect(await Vault.usesPhrase(file), isTrue);

      final vault = await Vault.unlock(file, 'secret1');
      expect(vault.hasLegacyRecovery, isTrue);
      expect(await vault.read(), '{"note":"старое"}');

      // Пока кода нет, доступ восстанавливается фразой.
      final byPhrase = await Vault.recover(file, validPhrase.toUpperCase());
      expect(await byPhrase.read(), '{"note":"старое"}');
      await expectLater(
        Vault.recover(file, Vault.newRecoveryCode()),
        throwsA(isA<WrongSecretException>()),
      );

      final code = Vault.newRecoveryCode();
      await vault.setRecoveryCode(code);
      expect(vault.hasLegacyRecovery, isFalse);
      expect(await Vault.usesPhrase(file), isFalse);
      expect(
        await (await Vault.recover(file, code)).read(),
        '{"note":"старое"}',
      );
      await expectLater(
        Vault.recover(file, validPhrase),
        throwsA(isA<WrongSecretException>()),
      );
      expect(
        await (await Vault.unlock(file, 'secret1')).read(),
        '{"note":"старое"}',
      );
    },
  );

  test('повреждённый и чужой файл', () async {
    await Vault.create(
      file,
      password: 'secret1',
      recoveryCode: Vault.newRecoveryCode(),
      data: '{}',
      kdf: fastKdf,
    );
    final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final data = doc['data'] as Map<String, dynamic>;
    final cipher = base64Decode(data['cipher'] as String)..[0] ^= 1;
    data['cipher'] = base64Encode(cipher);
    file.writeAsStringSync(jsonEncode(doc));
    final vault = await Vault.unlock(file, 'secret1');
    await expectLater(vault.read(), throwsA(isA<VaultFormatException>()));

    file.writeAsStringSync('{"months": []}');
    await expectLater(
      Vault.unlock(file, 'secret1'),
      throwsA(isA<VaultFormatException>()),
    );
  });

  test('первый запуск переносит budget.json прежней версии', () async {
    final old = BudgetData.template(DateTime(2026, 9))
      ..months.first.title = 'Мой сентябрь';
    final legacy = File('${dir.path}${Platform.pathSeparator}budget.json')
      ..writeAsStringSync(jsonEncode(old.toJson()));

    final store = await BudgetStore.create(
      dir,
      password: 'secret1',
      recoveryCode: Vault.newRecoveryCode(),
      kdf: fastKdf,
    );
    expect(store.data.months.first.title, 'Мой сентябрь');
    expect(legacy.existsSync(), isFalse);
    expect(file.readAsStringSync(), isNot(contains('Мой сентябрь')));

    // Изменения сохраняются в зашифрованный файл.
    store.edit((d) => d.debts.add(Debt(amount: '500', creditor: 'Аня')));
    await store.save();
    store.dispose();
    final reopened = await BudgetStore.open(
      await Vault.unlock(file, 'secret1'),
    );
    expect(reopened.data.months.first.title, 'Мой сентябрь');
    expect(reopened.data.debts.single.creditor, 'Аня');
  });

  test('без прежних данных — пустой шаблон', () async {
    final store = await BudgetStore.create(
      dir,
      password: 'secret1',
      recoveryCode: Vault.newRecoveryCode(),
      kdf: fastKdf,
    );
    final now = DateTime.now();
    expect(store.data.months.single.title, monthTitle(now.year, now.month));
    expect(store.data.months.single.sources.single.balance, '');
  });
}

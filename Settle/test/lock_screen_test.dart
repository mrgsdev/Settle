import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settle/main.dart';
import 'package:settle/model/store.dart';
import 'package:settle/security/vault.dart';

import 'test_fonts.dart';
import 'vault_helpers.dart';

void main() {
  final shots = Platform.environment['KT_SHOTS'];
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('settle_lock_'));
  tearDown(() => dir.deleteSync(recursive: true));
  final appKey = GlobalKey();
  String? clipboard;

  /// Ждём настоящих асинхронных операций (Argon2id в изоляте, файлы).
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Не дождались: $finder');
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (shots == null) return;
    await tester.pumpAndSettle();
    final boundary =
        appKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$shots/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> launch(WidgetTester tester) async {
    await tester.runAsync(loadTestFonts);
    tester.view.physicalSize = const Size(1200, 900) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    clipboard = null;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: appKey,
        child: SettleApp(dataDir: dir, kdf: fastKdf),
      ),
    );
    await waitFor(tester, find.byType(TextField));
    // Картинка логотипа декодируется асинхронно.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  /// Экран с кодом → «Скопировать» → «Я записал(а) код» → ввод кода → приложение.
  Future<String> confirmCode(WidgetTester tester, {String? shotName}) async {
    await tester.tap(find.text('Скопировать'));
    await tester.pump();
    final code = clipboard!;
    expect(Vault.codeError(code), isNull);
    for (final ch in code.split('')) {
      expect(find.text(ch), findsWidgets);
    }
    if (shotName != null) await shot(tester, shotName);

    // «Далее» доступно только после отметки.
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    expect(find.text('Проверка кода'), findsNothing);
    await tester.tap(find.text('Я записал(а) код'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    expect(find.text('Проверка кода'), findsOneWidget);

    final input = find.byType(TextField);
    await tester.enterText(input, Vault.newRecoveryCode());
    await tester.tap(find.text('Готово'));
    await tester.pump();
    expect(find.textContaining('Код не совпадает'), findsOneWidget);
    await tester.enterText(
      input,
      '${code.substring(0, 5)} ${code.substring(5)}',
    );
    await tester.tap(find.text('Готово'));
    await waitFor(tester, find.text('Обзор'));
    return code;
  }

  testWidgets('первый запуск: пароль и код восстановления', (tester) async {
    await launch(tester);
    expect(find.text('Придумайте пароль'), findsOneWidget);
    await shot(tester, 'lock_1_create');

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'secret1');
    await tester.enterText(fields.at(1), 'secret2');
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    expect(find.text('Пароли не совпадают'), findsOneWidget);
    await tester.enterText(fields.at(0), '123');
    await tester.enterText(fields.at(1), '123');
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    expect(find.textContaining('не короче 6'), findsOneWidget);

    await tester.enterText(fields.at(0), 'secret1');
    await tester.enterText(fields.at(1), 'secret1');
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(find.text('Код восстановления'), findsOneWidget);
    final code = await confirmCode(tester, shotName: 'lock_2_code');
    expect(BudgetStore.vaultFile(dir).existsSync(), isTrue);
    await tester.pump(const Duration(seconds: 6)); // скрыть «Код скопирован»
    await shot(tester, 'lock_4_app');

    // Пароль и код открывают созданный файл.
    await tester.runAsync(() async {
      final file = BudgetStore.vaultFile(dir);
      await Vault.unlock(file, 'secret1');
      await Vault.recover(file, code);
    });
  });

  testWidgets('вход по паролю', (tester) async {
    await tester.runAsync(
      () => BudgetStore.create(
        dir,
        password: 'secret1',
        recoveryCode: Vault.newRecoveryCode(),
        kdf: fastKdf,
      ),
    );
    await launch(tester);
    expect(find.text('Вход'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'secret2');
    await tester.tap(find.text('Войти'));
    await waitFor(tester, find.text('Неверный пароль'));
    await shot(tester, 'lock_5_wrong');

    await tester.enterText(find.byType(TextField), 'secret1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await waitFor(tester, find.text('Обзор'));
  });

  testWidgets('восстановление по коду и новый пароль', (tester) async {
    final code = Vault.newRecoveryCode();
    await tester.runAsync(
      () => BudgetStore.create(
        dir,
        password: 'secret1',
        recoveryCode: code,
        kdf: fastKdf,
      ),
    );
    await launch(tester);
    await tester.tap(find.text('Забыли пароль?'));
    await tester.pumpAndSettle();
    expect(find.text('Восстановление доступа'), findsOneWidget);

    final input = find.byType(TextField);
    await tester.enterText(input, code.substring(0, 7));
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    expect(find.text('В коде 10 букв, сейчас 7'), findsOneWidget);

    await tester.enterText(input, Vault.newRecoveryCode());
    await tester.tap(find.text('Продолжить'));
    await waitFor(tester, find.text('Неверный код восстановления'));

    await tester.enterText(input, code);
    await shot(tester, 'lock_6_recover');
    await tester.tap(find.text('Продолжить'));
    await waitFor(tester, find.text('Новый пароль'));

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'newpass');
    await tester.enterText(fields.at(1), 'newpass');
    await tester.tap(find.text('Сохранить и войти'));
    await waitFor(tester, find.text('Обзор'));

    await tester.runAsync(() async {
      final file = BudgetStore.vaultFile(dir);
      await Vault.unlock(file, 'newpass');
      await expectLater(
        Vault.unlock(file, 'secret1'),
        throwsA(isA<WrongSecretException>()),
      );
    });
  });

  testWidgets('старый файл с фразой: после входа выдаётся код', (tester) async {
    final file = BudgetStore.vaultFile(dir);
    await tester.runAsync(
      () => writeLegacyVault(
        file,
        password: 'secret1',
        phrase: validPhrase,
        data: '{"months": []}',
      ),
    );
    await launch(tester);
    await tester.enterText(find.byType(TextField), 'secret1');
    await tester.tap(find.text('Войти'));
    await waitFor(tester, find.text('Новый код восстановления'));
    expect(find.textContaining('старая фраза'), findsOneWidget);
    expect(find.text('Назад'), findsNothing);
    final code = await confirmCode(tester, shotName: 'lock_3_upgrade');

    await tester.runAsync(() async {
      expect(await Vault.usesPhrase(file), isFalse);
      await Vault.recover(file, code);
      await expectLater(
        Vault.recover(file, validPhrase),
        throwsA(isA<WrongSecretException>()),
      );
    });
  });

  testWidgets('старый файл: восстановление фразой, затем код', (tester) async {
    final file = BudgetStore.vaultFile(dir);
    await tester.runAsync(
      () => writeLegacyVault(
        file,
        password: 'secret1',
        phrase: validPhrase,
        data: '{"months": []}',
      ),
    );
    await launch(tester);
    await tester.tap(find.text('Забыли пароль?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('12 слов'), findsOneWidget);
    await tester.enterText(find.byType(TextField), validPhrase);
    await tester.tap(find.text('Продолжить'));
    await waitFor(tester, find.text('Новый пароль'));

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'newpass');
    await tester.enterText(fields.at(1), 'newpass');
    await tester.tap(find.text('Сохранить и войти'));
    await waitFor(tester, find.text('Новый код восстановления'));
    final code = await confirmCode(tester);

    await tester.runAsync(() async {
      await Vault.unlock(file, 'newpass');
      await Vault.recover(file, code);
    });
  });
}

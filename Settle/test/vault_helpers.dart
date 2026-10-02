import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:cryptography/cryptography.dart';
import 'package:settle/security/vault.dart';

/// Облегчённый Argon2id, чтобы тесты шли быстро.
const fastKdf = PasswordKdf(memory: 256, iterations: 1);

/// Тестовый вектор BIP39: корректная фраза и та же с неверной контрольной суммой.
final validPhrase = '${'abandon ' * 11}about';
final badChecksum = ('abandon ' * 12).trim();

/// Файл первых версий Settle: доступ восстанавливается фразой из 12 слов
/// (ключ HKDF-SHA256 из энтропии фразы) — как его записывал прежний код.
Future<void> writeLegacyVault(
  File file, {
  required String password,
  required String phrase,
  required String data,
}) async {
  final aes = AesGcm.with256bits();
  final rnd = Random.secure();
  List<int> random(int n) => List.generate(n, (_) => rnd.nextInt(256));
  Future<Map<String, dynamic>> seal(List<int> key, List<int> plain) async {
    final box = await aes.encrypt(plain, secretKey: SecretKey(key));
    return {
      'nonce': base64Encode(box.nonce),
      'cipher': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  final dataKey = random(32);
  final passwordSalt = random(16), recoverySalt = random(16);
  final passwordKey =
      await (await Argon2id(
            memory: fastKdf.memory,
            iterations: fastKdf.iterations,
            parallelism: 1,
            hashLength: 32,
          ).deriveKey(
            secretKey: SecretKey(utf8.encode(password)),
            nonce: passwordSalt,
          ))
          .extractBytes();
  final recoveryKey =
      await (await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(
          Mnemonic.fromWords(words: phrase.split(' ')).entropy,
        ),
        nonce: recoverySalt,
        info: utf8.encode('settle recovery key'),
      )).extractBytes();
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    jsonEncode({
      'format': 'settle-vault',
      'version': 1,
      'password': {
        ...fastKdf.toJson(),
        'salt': base64Encode(passwordSalt),
        ...await seal(passwordKey, dataKey),
      },
      'recovery': {
        'kdf': 'hkdf-sha256',
        'salt': base64Encode(recoverySalt),
        ...await seal(recoveryKey, dataKey),
      },
      'data': await seal(dataKey, utf8.encode(data)),
    }),
  );
}

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:cryptography/cryptography.dart';

/// Неверный пароль или фраза восстановления.
class WrongSecretException implements Exception {
  const WrongSecretException();
}

/// Файл данных повреждён или создан неизвестной версией.
class VaultFormatException implements Exception {
  const VaultFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Параметры Argon2id для ключа из пароля.
class PasswordKdf {
  const PasswordKdf({
    required this.memory,
    required this.iterations,
    this.parallelism = 1,
  });

  /// 64 МиБ и 3 прохода — около секунды на обычном компьютере.
  static const standard = PasswordKdf(memory: 65536, iterations: 3);

  final int memory; // КиБ
  final int iterations;
  final int parallelism;

  Map<String, dynamic> toJson() => {
    'kdf': 'argon2id',
    'memory': memory,
    'iterations': iterations,
    'parallelism': parallelism,
  };

  factory PasswordKdf.fromJson(Map<String, dynamic> j) {
    if (j['kdf'] != 'argon2id') {
      throw const VaultFormatException('Неизвестный способ защиты пароля');
    }
    return PasswordKdf(
      memory: j['memory'] as int,
      iterations: j['iterations'] as int,
      parallelism: j['parallelism'] as int,
    );
  }
}

/// Зашифрованный файл с данными приложения.
///
/// Данные шифруются случайным ключом (AES-256-GCM). Этот ключ хранится в файле
/// дважды: зашифрованный ключом из пароля и ключом из кода восстановления
/// (оба — Argon2id). Поэтому по коду можно задать новый пароль, не теряя
/// данных. Без пароля и без кода данные не расшифровать.
///
/// Файлы первых версий вместо кода хранят фразу из 12 слов BIP39 (HKDF):
/// по ней по-прежнему можно восстановить доступ, а после входа фраза
/// заменяется кодом ([hasLegacyRecovery], [setRecoveryCode]).
class Vault {
  Vault._(this.file, this._doc, this._dataKey);

  final File file;
  final Map<String, dynamic> _doc;
  final List<int> _dataKey;
  Future<void> _saving = Future.value();

  static const _format = 'settle-vault';
  static const _version = 1;
  static final _aes = AesGcm.with256bits();
  static final _random = Random.secure();

  // ───────────────────────── Код восстановления ─────────────────────────

  static const codeLength = 10;

  /// Латиница обоих регистров без букв, которые легко спутать при записи
  /// от руки: нет I, O и строчных i, l, o, а у c, j, k, p, s, u, v, w, x, z
  /// (заглавная и строчная почти одинаковы) — только заглавные. 37 букв,
  /// 10 знаков — около 52 бит; подбирать мешает Argon2id.
  static const codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabdefghmnqrty';

  /// Новый код вида «KWJbhfKQJW».
  static String newRecoveryCode() => String.fromCharCodes(
    List.generate(
      codeLength,
      (_) => codeAlphabet.codeUnitAt(_random.nextInt(codeAlphabet.length)),
    ),
  );

  /// Код без пробелов и дефисов; у букв, которые бывают только заглавными
  /// (k → K, s → S), регистр исправляется сам.
  static String normalizeCode(String input) {
    final b = StringBuffer();
    for (final ch in input.replaceAll(RegExp(r'[\s-]'), '').split('')) {
      final upper = ch.toUpperCase();
      b.write(
        !codeAlphabet.contains(ch) && codeAlphabet.contains(upper) ? upper : ch,
      );
    }
    return b.toString();
  }

  /// Что не так с введённым кодом, или null.
  static String? codeError(String input) {
    final code = normalizeCode(input);
    final bad = {
      for (final ch in code.split(''))
        if (!codeAlphabet.contains(ch)) ch,
    };
    if (bad.isNotEmpty) return 'В коде нет символов: ${bad.join(' ')}';
    if (code.length != codeLength) {
      return 'В коде $codeLength букв, сейчас ${code.length}';
    }
    return null;
  }

  /// Чем восстанавливается доступ к файлу: true — фраза из 12 слов (первые
  /// версии), false — код восстановления.
  static Future<bool> usesPhrase(File file) async =>
      _isPhraseSlot((await _load(file))['recovery'] as Map<String, dynamic>);

  static bool _isPhraseSlot(Map<String, dynamic> slot) =>
      slot['kdf'] == 'hkdf-sha256';

  // ──────────────── Фраза из 12 слов (только для старых файлов) ────────────────

  /// Слова фразы: строчные, без лишних пробелов и переносов строк.
  static List<String> phraseWords(String input) => input
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();

  /// Что не так с введённой фразой, или null, если она корректна.
  static String? phraseError(String input) {
    final words = phraseWords(input);
    if (words.length != 12) {
      return 'Нужно 12 слов, сейчас ${words.length}';
    }
    final unknown = words.where((w) => !Language.english.list.contains(w));
    if (unknown.isNotEmpty) return 'Нет таких слов: ${unknown.join(', ')}';
    try {
      Mnemonic.fromWords(words: words);
    } catch (_) {
      return 'Фраза с ошибкой — проверьте порядок слов';
    }
    return null;
  }

  // ───────────────────────── Открытие и создание ─────────────────────────

  static Future<Vault> create(
    File file, {
    required String password,
    required String recoveryCode,
    required String data,
    PasswordKdf kdf = PasswordKdf.standard,
  }) async {
    final dataKey = _randomBytes(32);
    // Два Argon2id — параллельно, в двух изолятах.
    final (passwordSlot, recoverySlot) = await (
      _passwordSlot(password, dataKey, kdf),
      _recoverySlot(recoveryCode, dataKey, kdf),
    ).wait;
    final vault = Vault._(file, {
      'format': _format,
      'version': _version,
      'password': passwordSlot,
      'recovery': recoverySlot,
    }, dataKey);
    await file.parent.create(recursive: true);
    await vault.write(data);
    // Проверка: записанный файл расшифровывается обратно.
    final check = Vault._(file, await _load(file), dataKey);
    if (await check.read() != data) {
      throw const VaultFormatException('Не удалось проверить записанный файл');
    }
    return vault;
  }

  static Future<Vault> unlock(File file, String password) async {
    final doc = await _load(file);
    final slot = doc['password'] as Map<String, dynamic>;
    final key = await _passwordKey(
      password,
      _bytes(slot['salt']),
      PasswordKdf.fromJson(slot),
    );
    return Vault._(file, doc, await _decrypt(key, slot));
  }

  /// Открыть по коду восстановления (у старых файлов — по фразе из 12 слов);
  /// затем нужно задать новый пароль.
  static Future<Vault> recover(File file, String secret) async {
    final doc = await _load(file);
    final slot = doc['recovery'] as Map<String, dynamic>;
    final salt = _bytes(slot['salt']);
    final List<int> key;
    if (_isPhraseSlot(slot)) {
      if (phraseError(secret) != null) throw const WrongSecretException();
      key = await _phraseKey(secret, salt);
    } else {
      key = await _passwordKey(
        normalizeCode(secret),
        salt,
        PasswordKdf.fromJson(slot),
      );
    }
    return Vault._(file, doc, await _decrypt(key, slot));
  }

  /// Новый пароль; код восстановления и данные остаются прежними.
  Future<void> changePassword(String password) async {
    _doc['password'] = await _passwordSlot(password, _dataKey, _kdf);
    await _save();
  }

  /// Доступ восстанавливается старой фразой из 12 слов — её пора заменить кодом.
  bool get hasLegacyRecovery =>
      _isPhraseSlot(_doc['recovery'] as Map<String, dynamic>);

  /// Новый код восстановления; прежний код (или фраза) перестаёт работать.
  Future<void> setRecoveryCode(String code) async {
    _doc['recovery'] = await _recoverySlot(code, _dataKey, _kdf);
    await _save();
  }

  /// Параметры Argon2id этого файла (в тестах — облегчённые).
  PasswordKdf get _kdf =>
      PasswordKdf.fromJson(_doc['password'] as Map<String, dynamic>);

  Future<String> read() async {
    final data = _doc['data'] as Map<String, dynamic>?;
    if (data == null) return '';
    try {
      return utf8.decode(await _decrypt(_dataKey, data));
    } on WrongSecretException {
      throw const VaultFormatException('Файл данных повреждён');
    }
  }

  Future<void> write(String data) async {
    _doc['data'] = await _encrypt(_dataKey, utf8.encode(data));
    await _save();
  }

  /// Записи идут по очереди: во временный файл и затем переименование,
  /// чтобы файл никогда не оставался записанным наполовину.
  Future<void> _save() {
    final json = jsonEncode(_doc);
    final next = _saving.catchError((_) {}).then((_) async {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    });
    _saving = next;
    return next;
  }

  static Future<Map<String, dynamic>> _load(File file) async {
    final Object? doc;
    try {
      doc = jsonDecode(await file.readAsString());
    } on FormatException {
      throw const VaultFormatException('Файл данных повреждён');
    }
    if (doc is! Map<String, dynamic> || doc['format'] != _format) {
      throw const VaultFormatException('Это не файл данных Settle');
    }
    if ((doc['version'] as int? ?? 0) > _version) {
      throw const VaultFormatException(
        'Файл данных создан более новой версией Settle',
      );
    }
    return doc;
  }

  // ───────────────────────────── Ключи ─────────────────────────────

  static Future<Map<String, dynamic>> _passwordSlot(
    String password,
    List<int> dataKey,
    PasswordKdf kdf,
  ) async {
    final salt = _randomBytes(16);
    final key = await _passwordKey(password, salt, kdf);
    return {
      ...kdf.toJson(),
      'salt': base64Encode(salt),
      ...await _encrypt(key, dataKey),
    };
  }

  /// Код короче пароля по энтропии, поэтому ключ из него — тоже Argon2id.
  static Future<Map<String, dynamic>> _recoverySlot(
    String code,
    List<int> dataKey,
    PasswordKdf kdf,
  ) async {
    final salt = _randomBytes(16);
    final key = await _passwordKey(normalizeCode(code), salt, kdf);
    return {
      ...kdf.toJson(),
      'salt': base64Encode(salt),
      ...await _encrypt(key, dataKey),
    };
  }

  /// Argon2id — в отдельном изоляте, чтобы окно не подвисало.
  static Future<List<int>> _passwordKey(
    String password,
    List<int> salt,
    PasswordKdf kdf,
  ) {
    final (memory, iterations, parallelism) = (
      kdf.memory,
      kdf.iterations,
      kdf.parallelism,
    );
    return Isolate.run(() async {
      final key = await Argon2id(
        memory: memory,
        iterations: iterations,
        parallelism: parallelism,
        hashLength: 32,
      ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
      return key.extractBytes();
    });
  }

  /// Ключ из фразы старых файлов: в ней 128 бит случайности, хватало HKDF.
  static Future<List<int>> _phraseKey(String phrase, List<int> salt) async {
    final entropy = Mnemonic.fromWords(words: phraseWords(phrase)).entropy;
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(entropy),
      nonce: salt,
      info: utf8.encode('settle recovery key'),
    );
    return key.extractBytes();
  }

  static Future<Map<String, dynamic>> _encrypt(
    List<int> key,
    List<int> plain,
  ) async {
    final box = await _aes.encrypt(plain, secretKey: SecretKey(key));
    return {
      'nonce': base64Encode(box.nonce),
      'cipher': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  static Future<List<int>> _decrypt(
    List<int> key,
    Map<String, dynamic> j,
  ) async {
    final box = SecretBox(
      _bytes(j['cipher']),
      nonce: _bytes(j['nonce']),
      mac: Mac(_bytes(j['mac'])),
    );
    try {
      return await _aes.decrypt(box, secretKey: SecretKey(key));
    } on SecretBoxAuthenticationError {
      throw const WrongSecretException();
    }
  }

  static List<int> _bytes(Object? b64) => base64Decode(b64 as String);

  static List<int> _randomBytes(int n) =>
      List<int>.generate(n, (_) => _random.nextInt(256));
}

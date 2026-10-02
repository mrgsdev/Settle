import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart'
    show AESEngine, CBCBlockCipher, KeyParameter, ParametersWithIV;
import 'package:xml/xml.dart';

import 'cfb.dart';

/// Неверный пароль к книге Excel.
class WrongPasswordException implements Exception {
  const WrongPasswordException();
}

/// Книга зашифрована неподдерживаемым способом или повреждена.
class OfficeCryptoException implements Exception {
  const OfficeCryptoException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Пароль на книгу .xlsx — шифрование Office «Agile» (MS-OFFCRYPTO), как у
/// Excel 2010 и новее: AES-256, SHA-512, 100 000 повторов хеша. Такую книгу
/// Excel открывает, спросив пароль; книги, запароленные в Excel, читаются.
abstract final class OfficeCrypto {
  /// Книга с паролем: составной файл OLE с потоком EncryptedPackage.
  static bool isEncrypted(Uint8List bytes) {
    if (!Cfb.isCfb(bytes)) return false;
    try {
      return Cfb.read(bytes).containsKey('EncryptedPackage');
    } catch (_) {
      return false;
    }
  }

  /// Зашифровать .xlsx паролем — в отдельном изоляте (около полсекунды).
  static Future<Uint8List> encrypt(
    Uint8List xlsx,
    String password, {
    int spinCount = 100000,
  }) => Isolate.run(() => _Agile.encrypt(xlsx, password, spinCount));

  /// Расшифровать книгу; [WrongPasswordException] — неверный пароль.
  static Future<Uint8List> decrypt(Uint8List file, String password) =>
      Isolate.run(() => _Agile.decrypt(file, password));
}

abstract final class _Agile {
  // Константы блоков из MS-OFFCRYPTO 2.3.4.11–2.3.4.14.
  static const _verifierInputBlock = [
    0xfe,
    0xa7,
    0xd2,
    0x76,
    0x3b,
    0x4b,
    0x9e,
    0x79,
  ];
  static const _verifierValueBlock = [
    0xd7,
    0xaa,
    0x0f,
    0x6d,
    0x30,
    0x61,
    0x34,
    0x4e,
  ];
  static const _keyValueBlock = [
    0x14,
    0x6e,
    0x0b,
    0xe7,
    0xab,
    0xac,
    0xd0,
    0xd6,
  ];
  static const _hmacKeyBlock = [0x5f, 0xb2, 0xad, 0x01, 0x0c, 0xb9, 0xe1, 0xf6];
  static const _hmacValueBlock = [
    0xa0,
    0x67,
    0x7f,
    0x02,
    0xb2,
    0x2c,
    0x84,
    0x33,
  ];
  static const _segment = 4096;
  static final _random = Random.secure();

  static Uint8List encrypt(Uint8List package, String password, int spinCount) {
    const hash = crypto.sha512;
    const keyBytes = 32, blockSize = 16;
    final keySalt = _randomBytes(16);
    final passwordSalt = _randomBytes(16);
    final secretKey = _randomBytes(keyBytes);

    // Данные: размер и сегменты по 4096 байт, у каждого свой IV.
    final out = BytesBuilder(copy: false)
      ..add(
        (ByteData(
          8,
        )..setUint64(0, package.length, Endian.little)).buffer.asUint8List(),
      );
    for (var i = 0, o = 0; o < package.length; i++, o += _segment) {
      final part = Uint8List.sublistView(
        package,
        o,
        min(o + _segment, package.length),
      );
      out.add(
        _aes(true, secretKey, _segmentIv(hash, keySalt, i, blockSize), part),
      );
    }
    final encrypted = out.toBytes();

    // Контроль целостности: HMAC всего потока EncryptedPackage.
    final hmacKey = _randomBytes(64);
    final hmacValue = crypto.Hmac(hash, hmacKey).convert(encrypted).bytes;
    final hmacKeyIv = _fit(_hash(hash, [keySalt, _hmacKeyBlock]), blockSize);
    final hmacValueIv = _fit(
      _hash(hash, [keySalt, _hmacValueBlock]),
      blockSize,
    );

    // Ключ из пароля шифрует проверочные значения и ключ данных.
    final h = _passwordHash(hash, passwordSalt, password, spinCount);
    Uint8List key(List<int> block) => _fit(_hash(hash, [h, block]), keyBytes);
    final verifierInput = _randomBytes(16);
    final verifierValue = hash.convert(verifierInput).bytes;

    String b64(List<int> b) => base64Encode(b);
    const params =
        'blockSize="16" keyBits="256" hashSize="64" cipherAlgorithm="AES" '
        'cipherChaining="ChainingModeCBC" hashAlgorithm="SHA512"';
    final xml =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<encryption xmlns="http://schemas.microsoft.com/office/2006/encryption" '
        'xmlns:p="http://schemas.microsoft.com/office/2006/keyEncryptor/password" '
        'xmlns:c="http://schemas.microsoft.com/office/2006/keyEncryptor/certificate">'
        '<keyData saltSize="16" $params saltValue="${b64(keySalt)}"/>'
        '<dataIntegrity '
        'encryptedHmacKey="${b64(_aes(true, secretKey, hmacKeyIv, hmacKey))}" '
        'encryptedHmacValue="${b64(_aes(true, secretKey, hmacValueIv, hmacValue))}"/>'
        '<keyEncryptors><keyEncryptor uri="http://schemas.microsoft.com/office/2006/keyEncryptor/password">'
        '<p:encryptedKey spinCount="$spinCount" saltSize="16" $params '
        'saltValue="${b64(passwordSalt)}" '
        'encryptedVerifierHashInput="${b64(_aes(true, key(_verifierInputBlock), passwordSalt, verifierInput))}" '
        'encryptedVerifierHashValue="${b64(_aes(true, key(_verifierValueBlock), passwordSalt, verifierValue))}" '
        'encryptedKeyValue="${b64(_aes(true, key(_keyValueBlock), passwordSalt, secretKey))}"/>'
        '</keyEncryptor></keyEncryptors></encryption>';

    // Версия 4.4 (Agile), флаги 0x40, затем XML.
    final info = BytesBuilder()
      ..add([4, 0, 4, 0, 0x40, 0, 0, 0])
      ..add(utf8.encode(xml));
    return Cfb.write({
      ..._dataSpaces(),
      'EncryptionInfo': info.toBytes(),
      'EncryptedPackage': encrypted,
    });
  }

  static Uint8List decrypt(Uint8List file, String password) {
    final Map<String, Uint8List> streams;
    try {
      streams = Cfb.read(file);
    } on FormatException catch (e) {
      throw OfficeCryptoException('Файл повреждён: ${e.message}');
    }
    final info = streams['EncryptionInfo'];
    final package = streams['EncryptedPackage'];
    if (info == null || package == null || info.length < 8) {
      throw const OfficeCryptoException('Это не зашифрованная книга Excel');
    }
    if (info[0] != 4 || info[2] != 4) {
      throw const OfficeCryptoException(
        'Книга зашифрована старым способом (Excel 2007). '
        'Пересохраните её с паролем в новой версии Excel.',
      );
    }
    final doc = XmlDocument.parse(
      utf8.decode(info.sublist(8)).replaceFirst('﻿', ''),
    );
    XmlElement element(String name) => doc.descendantElements.firstWhere(
      (e) => e.localName == name,
      orElse: () =>
          throw const OfficeCryptoException('В книге нет описания пароля'),
    );
    String attr(XmlElement e, String name) =>
        e.getAttribute(name) ??
        (throw OfficeCryptoException('В описании шифрования нет «$name»'));
    int number(XmlElement e, String name) => int.parse(attr(e, name));
    List<int> bytes(XmlElement e, String name) => base64Decode(attr(e, name));

    final keyData = element('keyData');
    final encryptedKey = element('encryptedKey');
    for (final e in [keyData, encryptedKey]) {
      if (attr(e, 'cipherAlgorithm') != 'AES' ||
          attr(e, 'cipherChaining') != 'ChainingModeCBC') {
        throw const OfficeCryptoException(
          'Книга зашифрована неподдерживаемым способом',
        );
      }
    }

    // Проверка пароля и ключ данных.
    final pHash = _algorithm(attr(encryptedKey, 'hashAlgorithm'));
    final salt = bytes(encryptedKey, 'saltValue');
    final h = _passwordHash(
      pHash,
      salt,
      password,
      number(encryptedKey, 'spinCount'),
    );
    final keyBytes = number(encryptedKey, 'keyBits') ~/ 8;
    Uint8List key(List<int> block) => _fit(_hash(pHash, [h, block]), keyBytes);
    final input = _aes(
      false,
      key(_verifierInputBlock),
      salt,
      bytes(encryptedKey, 'encryptedVerifierHashInput'),
    ).sublist(0, number(encryptedKey, 'saltSize'));
    final value = _aes(
      false,
      key(_verifierValueBlock),
      salt,
      bytes(encryptedKey, 'encryptedVerifierHashValue'),
    );
    final expected = pHash.convert(input).bytes;
    for (var i = 0; i < expected.length; i++) {
      if (i >= value.length || expected[i] != value[i]) {
        throw const WrongPasswordException();
      }
    }
    final secretKey = _aes(
      false,
      key(_keyValueBlock),
      salt,
      bytes(encryptedKey, 'encryptedKeyValue'),
    ).sublist(0, number(keyData, 'keyBits') ~/ 8);

    // Данные по сегментам.
    final kHash = _algorithm(attr(keyData, 'hashAlgorithm'));
    final kSalt = bytes(keyData, 'saltValue');
    final blockSize = number(keyData, 'blockSize');
    final size = ByteData.sublistView(
      package,
      0,
      8,
    ).getUint64(0, Endian.little);
    final out = BytesBuilder(copy: false);
    for (var i = 0, o = 8; o < package.length; i++, o += _segment) {
      final end = min(o + _segment, package.length);
      final part = Uint8List.sublistView(package, o, o + ((end - o) & ~15));
      out.add(
        _aes(false, secretKey, _segmentIv(kHash, kSalt, i, blockSize), part),
      );
    }
    final data = out.toBytes();
    if (size > data.length) {
      throw const OfficeCryptoException('Файл повреждён: данные обрезаны');
    }
    return Uint8List.sublistView(data, 0, size);
  }

  // ───────────────────────────── Примитивы ─────────────────────────────

  static crypto.Hash _algorithm(String name) => switch (name) {
    'SHA1' => crypto.sha1,
    'SHA256' => crypto.sha256,
    'SHA384' => crypto.sha384,
    'SHA512' => crypto.sha512,
    _ => throw OfficeCryptoException('Хеш $name не поддерживается'),
  };

  static List<int> _hash(crypto.Hash hash, List<List<int>> parts) =>
      hash.convert([for (final p in parts) ...p]).bytes;

  /// H0 = H(соль + пароль в UTF-16LE), затем spinCount раз H(номер + H).
  static List<int> _passwordHash(
    crypto.Hash hash,
    List<int> salt,
    String password,
    int spinCount,
  ) {
    final utf16 = [
      for (final u in password.codeUnits) ...[u & 0xFF, u >> 8],
    ];
    var h = hash.convert([...salt, ...utf16]).bytes;
    final buf = Uint8List(4 + h.length);
    final view = ByteData.sublistView(buf);
    for (var i = 0; i < spinCount; i++) {
      view.setUint32(0, i, Endian.little);
      buf.setRange(4, buf.length, h);
      h = hash.convert(buf).bytes;
    }
    return h;
  }

  static Uint8List _segmentIv(
    crypto.Hash hash,
    List<int> salt,
    int index,
    int blockSize,
  ) {
    final i = (ByteData(
      4,
    )..setUint32(0, index, Endian.little)).buffer.asUint8List();
    return _fit(_hash(hash, [salt, i]), blockSize);
  }

  /// Длина n: лишнее обрезается, недостающее дополняется байтами 0x36.
  static Uint8List _fit(List<int> b, int n) => Uint8List.fromList(
    b.length >= n
        ? b.sublist(0, n)
        : [...b, ...List.filled(n - b.length, 0x36)],
  );

  /// AES-CBC без дополнения: длина выравнивается нулями до 16 байт.
  static Uint8List _aes(
    bool encrypt,
    List<int> key,
    List<int> iv,
    List<int> data,
  ) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(
        encrypt,
        ParametersWithIV(
          KeyParameter(Uint8List.fromList(key)),
          Uint8List.fromList(iv),
        ),
      );
    final input = Uint8List((data.length + 15) & ~15)..setAll(0, data);
    final out = Uint8List(input.length);
    for (var o = 0; o < input.length; o += 16) {
      cipher.processBlock(input, o, out, o);
    }
    return out;
  }

  static Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  /// Служебные потоки \x06DataSpaces: «EncryptedPackage зашифрован
  /// преобразованием StrongEncryptionTransform» (MS-OFFCRYPTO 2.2).
  static Map<String, Uint8List> _dataSpaces() {
    List<int> u32(int v) =>
        (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();
    List<int> lpp4(String s) => [
      ...u32(s.length * 2),
      for (final u in s.codeUnits) ...[u & 0xFF, u >> 8],
      if (s.length.isOdd) ...[0, 0],
    ];
    const versions = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]; // 1.0 ×3, UInt16
    final entry = [
      ...u32(1),
      ...u32(0),
      ...lpp4('EncryptedPackage'),
      ...lpp4('StrongEncryptionDataSpace'),
    ];
    final transformId = lpp4('{FF9A3F03-56EF-4613-BDD5-5A41C1D07246}');
    return {
      '\u0006DataSpaces/Version': [
        ...lpp4('Microsoft.Container.DataSpaces'),
        ...versions,
      ],
      '\u0006DataSpaces/DataSpaceMap': [
        ...u32(8),
        ...u32(1),
        ...u32(entry.length + 4),
        ...entry,
      ],
      '\u0006DataSpaces/DataSpaceInfo/StrongEncryptionDataSpace': [
        ...u32(8),
        ...u32(1),
        ...lpp4('StrongEncryptionTransform'),
      ],
      '\u0006DataSpaces/TransformInfo/StrongEncryptionTransform/\u0006Primary':
          [
            ...u32(8 + transformId.length),
            ...u32(1),
            ...transformId,
            ...lpp4('Microsoft.Container.EncryptionTransform'),
            ...versions,
            ...u32(0), // имя шифрования — пустое
            ...u32(0), // размер блока
            ...u32(0), // режим
            ...u32(4), // зарезервировано, всегда 4
          ],
    }.map((k, v) => MapEntry(k, Uint8List.fromList(v)));
  }
}

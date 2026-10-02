import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Значение ячейки, прочитанное из XLSX.
class RCell {
  final String? text;
  final double? number;
  final bool? boolean;
  final String? formula;
  final String? error;

  const RCell({this.text, this.number, this.boolean, this.formula, this.error});

  bool get isEmpty =>
      (text == null || text!.trim().isEmpty) &&
      number == null &&
      boolean == null &&
      formula == null &&
      error == null;

  /// Текстовое представление (для строковых колонок).
  String get asText {
    if (text != null) return text!;
    if (number != null) {
      final n = number!;
      return n == n.truncateToDouble() && n.abs() < 1e15
          ? n.toInt().toString()
          : n.toString();
    }
    if (boolean != null) return boolean! ? 'ИСТИНА' : 'ЛОЖЬ';
    return '';
  }
}

class RSheet {
  RSheet(this.name);
  final String name;
  final Map<int, Map<int, RCell>> rows = {};

  RCell? cell(int row, int col) => rows[row]?[col];
  String text(int row, int col) => cell(row, col)?.asText.trim() ?? '';

  int get maxRow =>
      rows.isEmpty ? 0 : rows.keys.reduce((a, b) => a > b ? a : b);
}

class RBook {
  final Map<String, RSheet> sheets;
  final bool date1904;
  RBook(this.sheets, this.date1904);

  /// Поиск листа без учёта регистра и пробелов по краям.
  RSheet? sheet(String name) {
    final key = name.trim().toLowerCase();
    for (final e in sheets.entries) {
      if (e.key.trim().toLowerCase() == key) return e.value;
    }
    return null;
  }
}

class XlsxFormatException implements Exception {
  final String message;
  XlsxFormatException(this.message);
  @override
  String toString() => message;
}

class XlsxReader {
  static RBook read(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw XlsxFormatException('Файл не похож на книгу Excel (.xlsx).');
    }

    String? part(String path) {
      final p = path.startsWith('/') ? path.substring(1) : path;
      final f = archive.findFile(p);
      if (f == null) return null;
      return utf8.decode(f.content, allowMalformed: true);
    }

    final wbXml = part('xl/workbook.xml');
    if (wbXml == null) {
      throw XlsxFormatException(
        'В файле нет xl/workbook.xml — это не книга Excel.',
      );
    }
    final wb = XmlDocument.parse(wbXml);

    final date1904 = wb.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'workbookPr')
        .any(
          (e) =>
              (e.getAttribute('date1904') ?? '') == '1' ||
              (e.getAttribute('date1904') ?? '') == 'true',
        );

    // rId → путь листа
    final rels = <String, String>{};
    final relsXml = part('xl/_rels/workbook.xml.rels');
    if (relsXml != null) {
      for (final r in XmlDocument.parse(
        relsXml,
      ).descendants.whereType<XmlElement>()) {
        if (r.name.local != 'Relationship') continue;
        final id = r.getAttribute('Id');
        var target = r.getAttribute('Target');
        if (id == null || target == null) continue;
        if (target.startsWith('/')) {
          target = target.substring(1);
        } else {
          target = 'xl/$target';
        }
        rels[id] = target;
      }
    }

    final shared = <String>[];
    final sstXml = part('xl/sharedStrings.xml');
    if (sstXml != null) {
      for (final si in XmlDocument.parse(sstXml).rootElement.childElements) {
        if (si.name.local != 'si') continue;
        shared.add(_richText(si));
      }
    }

    final sheets = <String, RSheet>{};
    var index = 0;
    for (final s in wb.descendants.whereType<XmlElement>()) {
      if (s.name.local != 'sheet') continue;
      index++;
      final name = s.getAttribute('name') ?? 'Лист$index';
      final rid =
          s.attributes
              .where((a) => a.name.local == 'id')
              .map((a) => a.value)
              .firstOrNull ??
          '';
      final path = rels[rid] ?? 'xl/worksheets/sheet$index.xml';
      final xml = part(path);
      if (xml == null) continue;
      sheets[name] = _readSheet(name, xml, shared);
    }
    return RBook(sheets, date1904);
  }

  static String _richText(XmlElement si) {
    final b = StringBuffer();
    for (final e in si.descendants.whereType<XmlElement>()) {
      if (e.name.local != 't') continue;
      // Фонетические подсказки (rPh) не являются частью текста.
      if (e.ancestors.whereType<XmlElement>().any(
        (a) => a.name.local == 'rPh',
      )) {
        continue;
      }
      b.write(e.innerText);
    }
    return b.toString();
  }

  static (int, int)? parseRef(String ref) {
    final m = RegExp(r'^\$?([A-Za-z]+)\$?(\d+)$').firstMatch(ref);
    if (m == null) return null;
    var col = 0;
    for (final ch in m.group(1)!.toUpperCase().codeUnits) {
      col = col * 26 + (ch - 64);
    }
    return (int.parse(m.group(2)!), col);
  }

  static RSheet _readSheet(String name, String xml, List<String> shared) {
    final sheet = RSheet(name);
    final doc = XmlDocument.parse(xml);
    var lastRow = 0;
    for (final row in doc.descendants.whereType<XmlElement>()) {
      if (row.name.local != 'row') continue;
      final rAttr = int.tryParse(row.getAttribute('r') ?? '');
      final rowNum = rAttr ?? lastRow + 1;
      lastRow = rowNum;
      var lastCol = 0;
      for (final c in row.childElements) {
        if (c.name.local != 'c') continue;
        final pos = parseRef(c.getAttribute('r') ?? '');
        final col = pos?.$2 ?? lastCol + 1;
        lastCol = col;
        final t = c.getAttribute('t') ?? 'n';
        String? v, f, inline;
        for (final ch in c.childElements) {
          switch (ch.name.local) {
            case 'v':
              v = ch.innerText;
            case 'f':
              f = ch.innerText;
            case 'is':
              inline = _richText(ch);
          }
        }
        RCell cell;
        switch (t) {
          case 's':
            final i = int.tryParse(v ?? '');
            cell = RCell(
              text: i != null && i < shared.length ? shared[i] : '',
              formula: f,
            );
          case 'inlineStr':
            cell = RCell(text: inline ?? v ?? '', formula: f);
          case 'str':
            cell = RCell(text: v ?? '', formula: f);
          case 'b':
            cell = RCell(boolean: v == '1', formula: f);
          case 'e':
            cell = RCell(error: v, formula: f);
          default:
            cell = RCell(
              number: v == null ? null : double.tryParse(v),
              formula: f,
            );
        }
        if (!cell.isEmpty) (sheet.rows[rowNum] ??= {})[col] = cell;
      }
    }
    return sheet;
  }
}

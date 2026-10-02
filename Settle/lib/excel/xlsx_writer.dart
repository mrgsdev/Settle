import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'templates.dart';

/// Минимальный, но полноценный писатель XLSX (Office Open XML).
///
/// Формулы записываются как настоящие формулы Excel вместе с вычисленным
/// значением (кэшем), поэтому файл сразу показывает числа в Quick Look,
/// Numbers и предпросмотрах, а Excel/LibreOffice пересчитают их при открытии.

/// Индексы стилей из исходного файла (xl/styles.xml → cellXfs).
abstract final class XStyle {
  static const none = 0;
  static const headerBold = 1; // жирный, рамка, по центру
  static const headerBold2 = 2;
  static const text3 = 3; // обычный, рамка, по центру
  static const text = 4;
  static const money = 5; // бухгалтерский ₽
  static const fillOrange = 6; // светло-оранжевая заливка
  static const moneyCenter = 7;
  static const fillBlue = 8; // светло-голубая заливка
  static const borderOnly = 9;
  static const moneyBold = 10;
  static const textPlain = 11;
  static const moneyBlue = 12; // Сальдо
  static const percentOrange = 13; // Изменение в %
  static const monthTitle = 14; // заголовок блока месяца
  static const monthDate = 15; // дата блока месяца
  static const expHeaderMonth = 16;
  static const expHeader = 17;
  static const mandTitleL = 18;
  static const mandTitleM = 19;
  static const mandTitleR = 20;
  static const expHeaderMonth2 = 21;
  static const expHeader2 = 22;
  static const dayDate = 23; // д-ммм
  static const wrap = 24;
  static const numWrap = 25; // #,##0, перенос
  static const mandSumLabel = 26;
  static const mandSum = 27;
  static const int0 = 29; // #,##0
  static const prevLabel = 30;
  static const prevMid = 31;
  static const prevValue = 32;
  static const restLabel = 33;
  static const restValue = 34;
  static const budgetLabel = 35;
  static const budgetMid = 36;
  static const budgetValue = 37;
  static const monthName = 38;
  static const num2 = 39; // #,##0.00
  static const num2Fill = 41;
  static const rubInt = 43; // #,##0 "₽"
  static const boldNum2 = 44;
  static const percent = 45;
  static const moneyBoldCenter = 46;
  static const percentBold = 47;
  // Дополнительные стили приложения (добавлены в конец cellXfs):
  static const date = 48;
  static const textWrapCenter = 49;
}

class XCell {
  final int style;
  final String? text;
  final double? number;
  final String? formula;
  final String? error; // кэш формулы с ошибкой, например #DIV/0!

  const XCell({
    this.style = 0,
    this.text,
    this.number,
    this.formula,
    this.error,
  });

  const XCell.empty(this.style)
    : text = null,
      number = null,
      formula = null,
      error = null;
}

class XSheet {
  XSheet(this.name);

  final String name;
  final Map<int, Map<int, XCell>> _rows = {};
  final List<String> merges = [];
  final Map<int, double> colWidths = {};
  final Map<int, double> rowHeights = {};
  int? zoom;
  bool selected = false;

  void set(int row, int col, XCell cell) => (_rows[row] ??= {})[col] = cell;

  void merge(int r1, int c1, int r2, int c2) =>
      merges.add('${ref(r1, c1)}:${ref(r2, c2)}');

  static String colName(int col) {
    var c = col;
    var s = '';
    while (c > 0) {
      final m = (c - 1) % 26;
      s = String.fromCharCode(65 + m) + s;
      c = (c - m - 1) ~/ 26;
    }
    return s;
  }

  static String ref(int row, int col) => '${colName(col)}$row';
}

class XlsxWriter {
  XlsxWriter({this.creator = 'Settle'});

  final String creator;
  final List<XSheet> sheets = [];

  XSheet addSheet(String name) {
    final s = XSheet(name);
    sheets.add(s);
    return s;
  }

  final List<String> _sst = [];
  final Map<String, int> _sstIndex = {};
  int _sstCount = 0;

  int _str(String s) {
    _sstCount++;
    return _sstIndex.putIfAbsent(s, () {
      _sst.add(s);
      return _sst.length - 1;
    });
  }

  Uint8List build() {
    final archive = Archive();
    void add(String name, String content) =>
        archive.addFile(ArchiveFile.string(name, content));

    // Листы строим первыми — они наполняют таблицу общих строк.
    final sheetXml = [for (final s in sheets) _sheetXml(s)];

    add('[Content_Types].xml', _contentTypes());
    add('_rels/.rels', _rootRels);
    add('docProps/app.xml', _appXml());
    add('docProps/core.xml', _coreXml());
    add('xl/workbook.xml', _workbookXml());
    add('xl/_rels/workbook.xml.rels', _workbookRels());
    add('xl/styles.xml', kStylesXml);
    add('xl/theme/theme1.xml', kThemeXml);
    add('xl/sharedStrings.xml', _sharedStringsXml());
    for (var i = 0; i < sheets.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', sheetXml[i]);
    }
    return ZipEncoder().encodeBytes(archive);
  }

  static const _header =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
  static const _ns =
      'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  static const _nsR =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  static String esc(String s) {
    final b = StringBuffer();
    for (final ch in s.runes) {
      switch (ch) {
        case 0x26:
          b.write('&amp;');
        case 0x3C:
          b.write('&lt;');
        case 0x3E:
          b.write('&gt;');
        case 0x22:
          b.write('&quot;');
        default:
          // Управляющие символы XML 1.0 не допускает (кроме таба и переводов строк).
          if (ch < 0x20 && ch != 0x09 && ch != 0x0A && ch != 0x0D) continue;
          b.writeCharCode(ch);
      }
    }
    return b.toString();
  }

  static String _num(double n) {
    if (n == n.truncateToDouble() && n.abs() < 1e15) {
      return n.toInt().toString();
    }
    return n.toString();
  }

  String _sheetXml(XSheet s) {
    final b = StringBuffer(_header);
    b.write('<worksheet xmlns="$_ns" xmlns:r="$_nsR">');

    var maxRow = 1, maxCol = 1;
    for (final e in s._rows.entries) {
      if (e.value.isEmpty) continue;
      if (e.key > maxRow) maxRow = e.key;
      for (final c in e.value.keys) {
        if (c > maxCol) maxCol = c;
      }
    }
    b.write('<dimension ref="A1:${XSheet.ref(maxRow, maxCol)}"/>');

    b.write('<sheetViews><sheetView workbookViewId="0"');
    if (s.selected) b.write(' tabSelected="1"');
    if (s.zoom != null) {
      b.write(' zoomScale="${s.zoom}" zoomScaleNormal="${s.zoom}"');
    }
    b.write('/></sheetViews>');
    b.write('<sheetFormatPr defaultRowHeight="15"/>');

    if (s.colWidths.isNotEmpty) {
      b.write('<cols>');
      final cols = s.colWidths.keys.toList()..sort();
      for (final c in cols) {
        b.write(
          '<col min="$c" max="$c" width="${s.colWidths[c]}" customWidth="1"/>',
        );
      }
      b.write('</cols>');
    }

    b.write('<sheetData>');
    final rows = s._rows.keys.toList()..sort();
    for (final r in rows) {
      final cells = s._rows[r]!;
      b.write('<row r="$r"');
      final ht = s.rowHeights[r];
      if (ht != null) b.write(' ht="$ht" customHeight="1"');
      b.write('>');
      final cols = cells.keys.toList()..sort();
      for (final c in cols) {
        final cell = cells[c]!;
        final ref = XSheet.ref(r, c);
        final st = cell.style != 0 ? ' s="${cell.style}"' : '';
        if (cell.formula != null) {
          final f = '<f>${esc(cell.formula!)}</f>';
          if (cell.error != null) {
            b.write('<c r="$ref"$st t="e">$f<v>${esc(cell.error!)}</v></c>');
          } else if (cell.number != null) {
            b.write('<c r="$ref"$st>$f<v>${_num(cell.number!)}</v></c>');
          } else {
            b.write('<c r="$ref"$st>$f</c>');
          }
        } else if (cell.text != null && cell.text!.isNotEmpty) {
          b.write('<c r="$ref"$st t="s"><v>${_str(cell.text!)}</v></c>');
        } else if (cell.number != null) {
          b.write('<c r="$ref"$st><v>${_num(cell.number!)}</v></c>');
        } else {
          b.write('<c r="$ref"$st/>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData>');

    if (s.merges.isNotEmpty) {
      b.write('<mergeCells count="${s.merges.length}">');
      for (final m in s.merges) {
        b.write('<mergeCell ref="$m"/>');
      }
      b.write('</mergeCells>');
    }
    b.write(
      '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>',
    );
    b.write('</worksheet>');
    return b.toString();
  }

  String _sharedStringsXml() {
    final b = StringBuffer(_header);
    b.write(
      '<sst xmlns="$_ns" count="$_sstCount" uniqueCount="${_sst.length}">',
    );
    for (final s in _sst) {
      final preserve = s != s.trim() || s.contains('\n')
          ? ' xml:space="preserve"'
          : '';
      b.write('<si><t$preserve>${esc(s)}</t></si>');
    }
    b.write('</sst>');
    return b.toString();
  }

  String _workbookXml() {
    final b = StringBuffer(_header);
    b.write('<workbook xmlns="$_ns" xmlns:r="$_nsR">');
    b.write('<workbookPr defaultThemeVersion="164011"/>');
    b.write(
      '<bookViews><workbookView xWindow="0" yWindow="0" windowWidth="28800" windowHeight="12180"/></bookViews>',
    );
    b.write('<sheets>');
    for (var i = 0; i < sheets.length; i++) {
      b.write(
        '<sheet name="${esc(sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>',
      );
    }
    b.write('</sheets>');
    // fullCalcOnLoad — Excel пересчитает все формулы при открытии файла.
    b.write('<calcPr calcId="162913" fullCalcOnLoad="1"/>');
    b.write('</workbook>');
    return b.toString();
  }

  String _workbookRels() {
    final b = StringBuffer(_header);
    b.write(
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
    );
    final t =
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
    for (var i = 0; i < sheets.length; i++) {
      b.write(
        '<Relationship Id="rId${i + 1}" Type="$t/worksheet" Target="worksheets/sheet${i + 1}.xml"/>',
      );
    }
    final n = sheets.length;
    b.write(
      '<Relationship Id="rId${n + 1}" Type="$t/theme" Target="theme/theme1.xml"/>',
    );
    b.write(
      '<Relationship Id="rId${n + 2}" Type="$t/styles" Target="styles.xml"/>',
    );
    b.write(
      '<Relationship Id="rId${n + 3}" Type="$t/sharedStrings" Target="sharedStrings.xml"/>',
    );
    b.write('</Relationships>');
    return b.toString();
  }

  String _contentTypes() {
    final b = StringBuffer(_header);
    b.write(
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
    );
    b.write(
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
    );
    b.write('<Default Extension="xml" ContentType="application/xml"/>');
    const sml = 'application/vnd.openxmlformats-officedocument.spreadsheetml';
    b.write(
      '<Override PartName="/xl/workbook.xml" ContentType="$sml.sheet.main+xml"/>',
    );
    for (var i = 0; i < sheets.length; i++) {
      b.write(
        '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="$sml.worksheet+xml"/>',
      );
    }
    b.write(
      '<Override PartName="/xl/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>',
    );
    b.write(
      '<Override PartName="/xl/styles.xml" ContentType="$sml.styles+xml"/>',
    );
    b.write(
      '<Override PartName="/xl/sharedStrings.xml" ContentType="$sml.sharedStrings+xml"/>',
    );
    b.write(
      '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>',
    );
    b.write(
      '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>',
    );
    b.write('</Types>');
    return b.toString();
  }

  static const _rootRels =
      '$_header<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  String _appXml() {
    final b = StringBuffer(_header);
    b.write(
      '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
      'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">',
    );
    b.write(
      '<Application>Microsoft Excel</Application><DocSecurity>0</DocSecurity><ScaleCrop>false</ScaleCrop>',
    );
    b.write(
      '<HeadingPairs><vt:vector size="2" baseType="variant"><vt:variant><vt:lpstr>Листы</vt:lpstr></vt:variant>'
      '<vt:variant><vt:i4>${sheets.length}</vt:i4></vt:variant></vt:vector></HeadingPairs>',
    );
    b.write(
      '<TitlesOfParts><vt:vector size="${sheets.length}" baseType="lpstr">',
    );
    for (final s in sheets) {
      b.write('<vt:lpstr>${esc(s.name)}</vt:lpstr>');
    }
    b.write('</vt:vector></TitlesOfParts>');
    b.write(
      '<LinksUpToDate>false</LinksUpToDate><SharedDoc>false</SharedDoc>'
      '<HyperlinksChanged>false</HyperlinksChanged><AppVersion>16.0300</AppVersion></Properties>',
    );
    return b.toString();
  }

  String _coreXml() {
    final now = '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';
    return '$_header<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:creator>${esc(creator)}</dc:creator><cp:lastModifiedBy>${esc(creator)}</cp:lastModifiedBy>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified></cp:coreProperties>';
  }
}

/// Дата → серийный номер Excel (система 1900).
double excelSerial(DateTime d) {
  final utc = DateTime.utc(d.year, d.month, d.day);
  return utc.difference(DateTime.utc(1899, 12, 30)).inDays.toDouble();
}

/// Серийный номер Excel → дата.
DateTime fromExcelSerial(double serial, {bool date1904 = false}) {
  final base = date1904 ? DateTime.utc(1904, 1, 1) : DateTime.utc(1899, 12, 30);
  final d = base.add(Duration(milliseconds: (serial * 86400000).round()));
  return DateTime(d.year, d.month, d.day);
}

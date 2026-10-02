import 'dart:math' as math;
import 'dart:typed_data';

/// Составной файл OLE (Compound File Binary, MS-CFB) — контейнер, в котором
/// Office хранит зашифрованные книги. Поддерживается то, что нужно для них:
/// чтение версий 3 и 4, запись версии 3 (сектора по 512 байт).
class Cfb {
  Cfb._();

  static const _signature = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
  static const _free = 0xFFFFFFFF;
  static const _endOfChain = 0xFFFFFFFE;
  static const _fatSect = 0xFFFFFFFD;
  static const _difSect = 0xFFFFFFFC;
  static const _noStream = 0xFFFFFFFF;
  static const _miniCutoff = 4096;
  static const _miniSize = 64;

  static bool isCfb(Uint8List bytes) {
    if (bytes.length < 512) return false;
    for (var i = 0; i < _signature.length; i++) {
      if (bytes[i] != _signature[i]) return false;
    }
    return true;
  }

  // ───────────────────────────── Чтение ─────────────────────────────

  /// Все потоки файла: путь через «/» → содержимое.
  static Map<String, Uint8List> read(Uint8List bytes) {
    if (!isCfb(bytes)) throw const FormatException('Это не файл OLE');
    final h = ByteData.sublistView(bytes);
    final sectorSize = 1 << h.getUint16(0x1E, Endian.little);
    final miniSectorSize = 1 << h.getUint16(0x20, Endian.little);
    final cutoff = h.getUint32(0x38, Endian.little);
    final perSector = sectorSize ~/ 4;

    Uint8List sector(int i) {
      final start = (i + 1) * sectorSize;
      if (start + sectorSize > bytes.length) {
        throw const FormatException('Файл OLE обрезан');
      }
      return Uint8List.sublistView(bytes, start, start + sectorSize);
    }

    int u32(Uint8List b, int i) =>
        ByteData.sublistView(b).getUint32(i * 4, Endian.little);

    // DIFAT: 109 записей в заголовке + цепочка секторов DIFAT.
    final fatSectors = <int>[
      for (var i = 0; i < 109; i++) h.getUint32(0x4C + i * 4, Endian.little),
    ];
    var difat = h.getUint32(0x44, Endian.little);
    for (var guard = 0; difat < _difSect && guard < 1 << 16; guard++) {
      final s = sector(difat);
      for (var i = 0; i < perSector - 1; i++) {
        fatSectors.add(u32(s, i));
      }
      difat = u32(s, perSector - 1);
    }
    final fat = <int>[
      for (final s in fatSectors.where((s) => s < _difSect))
        for (var i = 0; i < perSector; i++) u32(sector(s), i),
    ];

    List<int> chain(List<int> table, int start) {
      final out = <int>[];
      for (var s = start; s < _difSect; s = table[s]) {
        if (s >= table.length || out.length > table.length) {
          throw const FormatException('Повреждённая цепочка секторов');
        }
        out.add(s);
      }
      return out;
    }

    Uint8List readChain(int start) {
      final b = BytesBuilder(copy: false);
      for (final s in chain(fat, start)) {
        b.add(sector(s));
      }
      return b.toBytes();
    }

    final dir = readChain(h.getUint32(0x30, Endian.little));
    final entries = <_Entry>[
      for (var o = 0; o + 128 <= dir.length; o += 128) _Entry.parse(dir, o),
    ];
    final root = entries.first;
    final miniStream = root.start < _difSect
        ? readChain(root.start)
        : Uint8List(0);
    final miniFatBytes = h.getUint32(0x3C, Endian.little) < _difSect
        ? readChain(h.getUint32(0x3C, Endian.little))
        : Uint8List(0);
    final miniFat = [
      for (var i = 0; i < miniFatBytes.length ~/ 4; i++) u32(miniFatBytes, i),
    ];

    Uint8List stream(_Entry e) {
      if (e.size == 0) return Uint8List(0);
      final Uint8List data;
      if (e.size < cutoff) {
        final b = BytesBuilder(copy: false);
        for (final s in chain(miniFat, e.start)) {
          final at = s * miniSectorSize;
          b.add(Uint8List.sublistView(miniStream, at, at + miniSectorSize));
        }
        data = b.toBytes();
      } else {
        data = readChain(e.start);
      }
      if (data.length < e.size) {
        throw const FormatException('Поток OLE обрезан');
      }
      return Uint8List.sublistView(data, 0, e.size);
    }

    final result = <String, Uint8List>{};
    void walk(int id, String prefix, int depth) {
      if (id == _noStream || id >= entries.length || depth > 64) return;
      final e = entries[id];
      walk(e.left, prefix, depth + 1);
      walk(e.right, prefix, depth + 1);
      if (e.type == 2) result['$prefix${e.name}'] = stream(e);
      if (e.type == 1) walk(e.child, '$prefix${e.name}/', depth + 1);
    }

    walk(root.child, '', 0);
    return result;
  }

  // ───────────────────────────── Запись ─────────────────────────────

  /// Файл из потоков; путь через «/» задаёт вложенные хранилища.
  static Uint8List write(Map<String, Uint8List> streams) {
    // Дерево каталогов.
    final root = _Node('Root Entry', 5);
    for (final MapEntry(key: path, value: data) in streams.entries) {
      final parts = path.split('/');
      var parent = root;
      for (final name in parts.take(parts.length - 1)) {
        parent = parent.children.firstWhere(
          (c) => c.name == name && c.type == 1,
          orElse: () {
            final s = _Node(name, 1);
            parent.children.add(s);
            return s;
          },
        );
      }
      parent.children.add(_Node(parts.last, 2, data));
    }
    final nodes = <_Node>[];
    void collect(_Node n) {
      n.id = nodes.length;
      nodes.add(n);
      n.children.sort(_Node.compare);
      n.children.forEach(collect);
    }

    collect(root);

    // Дети каждого хранилища — сбалансированным деревом, все узлы чёрные.
    int tree(List<_Node> sorted, int from, int to) {
      if (from >= to) return _noStream;
      final mid = (from + to) ~/ 2;
      sorted[mid]
        ..left = tree(sorted, from, mid)
        ..right = tree(sorted, mid + 1, to);
      return sorted[mid].id;
    }

    for (final n in nodes) {
      n.child = tree(n.children, 0, n.children.length);
    }

    // Маленькие потоки — в мини-поток по 64 байта, большие — в обычные сектора.
    final mini = BytesBuilder();
    final miniFat = <int>[];
    for (final n in nodes.where(
      (n) => n.type == 2 && n.data.length < _miniCutoff,
    )) {
      if (n.data.isEmpty) continue;
      final count = (n.data.length + _miniSize - 1) ~/ _miniSize;
      n.start = miniFat.length;
      for (var i = 0; i < count; i++) {
        miniFat.add(i == count - 1 ? _endOfChain : miniFat.length + 1);
      }
      mini.add(n.data);
      mini.add(Uint8List(count * _miniSize - n.data.length));
    }
    final miniStream = mini.toBytes();
    root.data = miniStream;

    const sectorSize = 512, perSector = 128;
    int sectorsFor(int bytes) => (bytes + sectorSize - 1) ~/ sectorSize;
    final dirSectors = sectorsFor(nodes.length * 128);
    final miniFatSectors = sectorsFor(miniFat.length * 4);
    final miniStreamSectors = sectorsFor(miniStream.length);
    final big = [
      for (final n in nodes)
        if (n.type == 2 && n.data.length >= _miniCutoff) n,
    ];
    final dataSectors =
        dirSectors +
        miniFatSectors +
        miniStreamSectors +
        big.fold(0, (sum, n) => sum + sectorsFor(n.data.length));

    // Число секторов FAT и DIFAT зависит само от себя — подбираем.
    var fatCount = 1, difatCount = 0;
    while (true) {
      final total = fatCount + difatCount + dataSectors;
      final needFat = (total + perSector - 1) ~/ perSector;
      final needDifat = math.max(0, (needFat - 109 + 126) ~/ 127);
      if (needFat == fatCount && needDifat == difatCount) break;
      fatCount = needFat;
      difatCount = needDifat;
    }

    final fat = List<int>.filled(fatCount * perSector, _free);
    var next = 0;
    final fatStart = next;
    for (var i = 0; i < fatCount; i++) {
      fat[next++] = _fatSect;
    }
    final difatStart = next;
    for (var i = 0; i < difatCount; i++) {
      fat[next++] = _difSect;
    }
    int allocate(int count) {
      if (count == 0) return _endOfChain;
      final start = next;
      for (var i = 0; i < count; i++) {
        fat[next] = i == count - 1 ? _endOfChain : next + 1;
        next++;
      }
      return start;
    }

    final dirStart = allocate(dirSectors);
    final miniFatStart = allocate(miniFatSectors);
    root.start = allocate(miniStreamSectors);
    for (final n in big) {
      n.start = allocate(sectorsFor(n.data.length));
    }

    final out = ByteData((next + 1) * sectorSize);
    final bytes = out.buffer.asUint8List();
    void put(int sector, Uint8List data) => bytes.setRange(
      (sector + 1) * sectorSize,
      (sector + 1) * sectorSize + data.length,
      data,
    );

    // Заголовок.
    bytes.setRange(0, 8, _signature);
    out
      ..setUint16(0x18, 0x003E, Endian.little)
      ..setUint16(0x1A, 0x0003, Endian.little)
      ..setUint16(0x1C, 0xFFFE, Endian.little)
      ..setUint16(0x1E, 9, Endian.little)
      ..setUint16(0x20, 6, Endian.little)
      ..setUint32(0x2C, fatCount, Endian.little)
      ..setUint32(0x30, dirStart, Endian.little)
      ..setUint32(0x38, _miniCutoff, Endian.little)
      ..setUint32(
        0x3C,
        miniFatSectors == 0 ? _endOfChain : miniFatStart,
        Endian.little,
      )
      ..setUint32(0x40, miniFatSectors, Endian.little)
      ..setUint32(
        0x44,
        difatCount == 0 ? _endOfChain : difatStart,
        Endian.little,
      )
      ..setUint32(0x48, difatCount, Endian.little);
    for (var i = 0; i < 109; i++) {
      out.setUint32(
        0x4C + i * 4,
        i < fatCount ? fatStart + i : _free,
        Endian.little,
      );
    }

    // Сектора DIFAT: номера секторов FAT сверх 109 и ссылка на следующий.
    for (var d = 0; d < difatCount; d++) {
      final s = ByteData(sectorSize);
      for (var i = 0; i < perSector - 1; i++) {
        final k = 109 + d * (perSector - 1) + i;
        s.setUint32(i * 4, k < fatCount ? fatStart + k : _free, Endian.little);
      }
      s.setUint32(
        sectorSize - 4,
        d == difatCount - 1 ? _endOfChain : difatStart + d + 1,
        Endian.little,
      );
      put(difatStart + d, s.buffer.asUint8List());
    }

    // FAT.
    final fatBytes = ByteData(fat.length * 4);
    for (var i = 0; i < fat.length; i++) {
      fatBytes.setUint32(i * 4, fat[i], Endian.little);
    }
    for (var i = 0; i < fatCount; i++) {
      put(
        fatStart + i,
        Uint8List.sublistView(fatBytes, i * sectorSize, (i + 1) * sectorSize),
      );
    }

    // Каталог.
    final dir = ByteData(dirSectors * sectorSize);
    for (var i = 0; i < dirSectors * 4; i++) {
      final o = i * 128;
      if (i >= nodes.length) {
        dir
          ..setUint32(o + 0x44, _noStream, Endian.little)
          ..setUint32(o + 0x48, _noStream, Endian.little)
          ..setUint32(o + 0x4C, _noStream, Endian.little);
        continue;
      }
      nodes[i].writeEntry(dir, o);
    }
    var at = dirStart;
    for (var i = 0; i < dirSectors; i++) {
      put(
        at + i,
        Uint8List.sublistView(dir, i * sectorSize, (i + 1) * sectorSize),
      );
    }

    // Мини-FAT, мини-поток, большие потоки.
    final mf = ByteData(miniFatSectors * sectorSize);
    for (var i = 0; i < miniFatSectors * perSector; i++) {
      mf.setUint32(
        i * 4,
        i < miniFat.length ? miniFat[i] : _free,
        Endian.little,
      );
    }
    for (var i = 0; i < miniFatSectors; i++) {
      put(
        miniFatStart + i,
        Uint8List.sublistView(mf, i * sectorSize, (i + 1) * sectorSize),
      );
    }
    if (miniStream.isNotEmpty) put(root.start, miniStream);
    for (final n in big) {
      put(n.start, n.data);
    }
    return bytes;
  }
}

class _Entry {
  _Entry(
    this.name,
    this.type,
    this.left,
    this.right,
    this.child,
    this.start,
    this.size,
  );

  final String name;
  final int type, left, right, child, start, size;

  factory _Entry.parse(Uint8List dir, int o) {
    final d = ByteData.sublistView(dir, o, o + 128);
    final nameLen = math.min(d.getUint16(0x40, Endian.little), 64);
    final units = [
      for (var i = 0; i + 1 < nameLen; i += 2) d.getUint16(i, Endian.little),
    ];
    while (units.isNotEmpty && units.last == 0) {
      units.removeLast();
    }
    return _Entry(
      String.fromCharCodes(units),
      d.getUint8(0x42),
      d.getUint32(0x44, Endian.little),
      d.getUint32(0x48, Endian.little),
      d.getUint32(0x4C, Endian.little),
      d.getUint32(0x74, Endian.little),
      d.getUint32(0x78, Endian.little),
    );
  }
}

class _Node {
  _Node(this.name, this.type, [Uint8List? data]) : data = data ?? Uint8List(0);

  final String name;
  final int type; // 1 — хранилище, 2 — поток, 5 — корень
  Uint8List data;
  final children = <_Node>[];
  int id = 0;
  int start = Cfb._endOfChain;
  int left = Cfb._noStream, right = Cfb._noStream, child = Cfb._noStream;

  /// Порядок имён в каталоге: сначала короче, затем по заглавным буквам.
  static int compare(_Node a, _Node b) {
    if (a.name.length != b.name.length) {
      return a.name.length - b.name.length;
    }
    return a.name.toUpperCase().compareTo(b.name.toUpperCase());
  }

  void writeEntry(ByteData d, int o) {
    final units = name.codeUnits;
    for (var i = 0; i < units.length; i++) {
      d.setUint16(o + i * 2, units[i], Endian.little);
    }
    d
      ..setUint16(o + 0x40, (units.length + 1) * 2, Endian.little)
      ..setUint8(o + 0x42, type)
      ..setUint8(o + 0x43, 1)
      ..setUint32(o + 0x44, left, Endian.little)
      ..setUint32(o + 0x48, right, Endian.little)
      ..setUint32(o + 0x4C, child, Endian.little)
      ..setUint32(o + 0x74, type == 1 ? 0 : start, Endian.little)
      ..setUint32(o + 0x78, type == 1 ? 0 : data.length, Endian.little);
  }
}

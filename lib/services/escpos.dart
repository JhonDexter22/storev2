import 'dart:typed_data';

/// How wide the paper is, in characters of the printer's default font.
///
/// Thermal printers have no notion of millimetres — everything is columns of a
/// fixed-width font, so this is the one number the whole layout hangs off.
enum PaperWidth {
  mm58('58 mm', 32),
  mm80('80 mm', 48);

  const PaperWidth(this.label, this.cols);

  final String label;
  final int cols;

  static PaperWidth byName(String? name) =>
      values.firstWhere((w) => w.name == name, orElse: () => mm58);
}

/// Builds an ESC/POS byte stream — the command language every cheap thermal
/// printer speaks.
///
/// Kept free of any Bluetooth or plugin code on purpose: what gets printed is
/// worth testing, and it can only be tested if producing it needs no printer.
class EscPos {
  EscPos(this.paper);

  final PaperWidth paper;
  final _out = BytesBuilder();

  int get cols => paper.cols;

  static const _esc = 0x1B;
  static const _gs = 0x1D;

  /// Wakes the printer and clears whatever state the last job left behind.
  ///
  /// Without this a receipt can arrive in double height because the previous
  /// one was cut off mid-command.
  void reset() {
    _out.add([_esc, 0x40]); // ESC @  — initialise
    _out.add([_esc, 0x74, 0x00]); // ESC t 0 — code page 437
  }

  void align(EscAlign a) => _out.add([_esc, 0x61, a.index]);

  void bold(bool on) => _out.add([_esc, 0x45, on ? 1 : 0]);

  /// Double width and height, for the one figure the customer looks for.
  void big(bool on) => _out.add([_gs, 0x21, on ? 0x11 : 0x00]);

  void feed(int lines) => _out.add([_esc, 0x64, lines]);

  /// Feeds the last line past the tear bar, then cuts if there is a cutter.
  ///
  /// Printers without one ignore the cut and the feed still does its job, so
  /// this is safe to send either way.
  void cut() {
    feed(4);
    _out.add([_gs, 0x56, 0x42, 0x00]); // GS V B 0 — partial cut
  }

  /// One line of text, already sized to fit.
  void line([String text = '']) {
    _out.add(encode(text));
    _out.add([0x0A]);
  }

  void lines(Iterable<String> texts) => texts.forEach(line);

  void rule() => line('-' * cols);

  Uint8List bytes() => _out.toBytes();

  // ---------------------------------------------------------------- encoding

  /// Code page 437 bytes for the accented characters that turn up in Filipino
  /// names — Niño and Peña should not print as Ni?o and Pe?a.
  static const _cp437 = <String, int>{
    'ü': 0x81, 'é': 0x82, 'â': 0x83, 'ä': 0x84, 'à': 0x85, 'å': 0x86,
    'ç': 0x87, 'ê': 0x88, 'ë': 0x89, 'è': 0x8A, 'ï': 0x8B, 'î': 0x8C,
    'ì': 0x8D, 'Ä': 0x8E, 'Å': 0x8F, 'É': 0x90, 'ô': 0x93, 'ö': 0x94,
    'ò': 0x95, 'û': 0x96, 'ù': 0x97, 'Ö': 0x99, 'Ü': 0x9A, 'á': 0xA0,
    'í': 0xA1, 'ó': 0xA2, 'ú': 0xA3, 'ñ': 0xA4, 'Ñ': 0xA5, '°': 0xF8,
  };

  /// Characters with no byte at all, written as the nearest thing that still
  /// reads correctly.
  ///
  /// The peso sign is the one that matters: code page 437 predates it and no
  /// common thermal code page carries it, so a receipt asking for ₱ prints a
  /// wrong glyph or nothing. "P50.00" is what these printers put on paper in
  /// the Philippines, so that is what this sends.
  static const _substitutes = <String, String>{
    '₱': 'P',
    '–': '-', '—': '-', '‑': '-',
    '‘': "'", '’': "'", '“': '"', '”': '"',
    '…': '...', '\t': ' ', ' ': ' ',
  };

  /// Text as code page 437 bytes. Anything with no representation becomes '?'
  /// rather than a byte the printer would read as a command.
  static Uint8List encode(String text) {
    final out = <int>[];
    for (final rune in text.runes) {
      if (rune == 0x0A) {
        out.add(0x0A);
        continue;
      }
      if (rune >= 0x20 && rune <= 0x7E) {
        out.add(rune);
        continue;
      }
      final ch = String.fromCharCode(rune);
      final direct = _cp437[ch];
      if (direct != null) {
        out.add(direct);
        continue;
      }
      final swap = _substitutes[ch];
      if (swap != null) {
        out.addAll(swap.codeUnits);
        continue;
      }
      out.add(0x3F); // '?'
    }
    return Uint8List.fromList(out);
  }

  // ------------------------------------------------------------------ layout

  /// Wraps at whole words, splitting any word too long to ever fit.
  ///
  /// The printer does its own wrapping, but it breaks mid-word and leaves the
  /// amount column stranded, so the text has to arrive already fitted.
  /// Leading spaces are kept and applied to every line the paragraph wraps
  /// onto: the indent is what makes a unit price read as belonging to the item
  /// above it rather than as a line of its own.
  static List<String> wrap(String text, int cols) {
    if (cols <= 0) return [text];
    final out = <String>[];
    for (final para in text.split('\n')) {
      final body = para.trimLeft();
      final indent = para.length - body.length;
      if (indent >= cols) {
        out.add(para);
        continue;
      }
      final room = cols - indent;
      final pad = ' ' * indent;

      var line = '';
      for (final word in body.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        var w = word;
        while (w.length > room) {
          if (line.isNotEmpty) {
            out.add(pad + line);
            line = '';
          }
          out.add(pad + w.substring(0, room));
          w = w.substring(room);
        }
        if (line.isEmpty) {
          line = w;
        } else if (line.length + 1 + w.length <= room) {
          line = '$line $w';
        } else {
          out.add(pad + line);
          line = w;
        }
      }
      out.add(pad + line);
    }
    return out;
  }

  /// A label on the left and a figure hard against the right edge.
  ///
  /// A long name wraps and the figure sits on the last line, so the amount
  /// column stays straight however long the product's name is.
  static List<String> row(String left, String right, int cols) {
    if (right.length >= cols) return [...wrap(left, cols), right.padLeft(cols)];
    final wrapped = wrap(left, cols - right.length - 1);
    final last = wrapped.removeLast();
    wrapped.add(last.padRight(cols - right.length) + right);
    return wrapped;
  }

  static List<String> centre(String text, int cols) =>
      [for (final l in wrap(text, cols)) _pad(l, cols)];

  static String _pad(String line, int cols) {
    final room = cols - line.length;
    return room <= 0 ? line : ' ' * (room ~/ 2) + line;
  }
}

enum EscAlign { left, centre, right }

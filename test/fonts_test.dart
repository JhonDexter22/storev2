import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:storev2/core/design_tokens.dart';

/// The fonts ship inside the app and the network is never asked for them, so
/// a weight used in code but missing from assets/fonts would fall back to the
/// system font in a shop — silently. These make it fail here instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('every weight the design uses loads from the bundle', () async {
    final styles = [
      AppText.screenTitle(),
      AppText.sectionTitle(),
      AppText.heroFigure(),
      AppText.largeFigure(),
      AppText.statFigure(),
      AppText.cardTitle(),
      AppText.body(),
      AppText.caption(),
      AppText.overline(),
      AppText.chip(),
      AppText.mono(),
      // Plain Text widgets inherit this theme, at the weights they ask for.
      for (final w in [FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700, FontWeight.w800])
        GoogleFonts.plusJakartaSans(fontWeight: w),
    ];
    GoogleFonts.plusJakartaSansTextTheme();
    expect(styles, isNotEmpty);

    await expectLater(GoogleFonts.pendingFonts(), completes);
  });

  test('no weight in the code is left out of the bundle', () {
    // Weights written anywhere under lib/ must each have a file, since the
    // theme applies Plus Jakarta Sans to every Text that sets one.
    const files = {
      400: 'Regular', 500: 'Medium', 600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold',
    };
    final used = <int>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final m in RegExp(r'FontWeight\.w(\d00)').allMatches(f.readAsStringSync())) {
        used.add(int.parse(m[1]!));
      }
    }
    for (final w in used) {
      expect(files, contains(w), reason: 'FontWeight.w$w is used but not bundled');
      expect(File('assets/fonts/PlusJakartaSans-${files[w]}.ttf').existsSync(), isTrue);
    }
  });

  test('the licences travel with the fonts', () {
    for (final f in ['OFL-PlusJakartaSans.txt', 'OFL-RobotoMono.txt']) {
      expect(File('assets/fonts/$f').readAsStringSync(),
          contains('SIL Open Font License'));
    }
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asset containing the full SIL OFL 1.1 text and attribution for the bundled
/// KT Kiyosuna Sans fonts. It is also listed in `pubspec.yaml` assets, so the
/// license travels with the APK.
const String kiyosunaLicenseAsset =
    'assets/fonts/KiyosunaSans/README.md';

bool _registered = false;

/// Registers the bundled Kiyosuna Sans license with Flutter's license registry
/// so `showLicensePage` displays the full OFL text and copyright notice.
void registerBundledFontLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(kiyosunaLicenseAsset);
    yield LicenseEntryWithLineBreaks(
      const <String>['Kiyosuna Sans', 'KT Kiyosuna Sans'],
      text,
    );
  });
}

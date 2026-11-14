import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/features/settings/storage_permission_prompt.dart';

void main() {
  test('detects external paths but not app-private directories', () {
    expect(pathNeedsAllFilesAccess('/sdcard/Download/unidic'), isTrue);
    expect(
      pathNeedsAllFilesAccess('/storage/emulated/0/Download/dict.mdx'),
      isTrue,
    );
    expect(
      pathNeedsAllFilesAccess(
        '/storage/emulated/0/Android/data/com.lexicandy.mobile/files/models',
      ),
      isFalse,
    );
    expect(
      pathNeedsAllFilesAccess('/data/user/0/com.lexicandy.mobile/files'),
      isFalse,
    );
    expect(pathNeedsAllFilesAccess(''), isFalse);
  });
}

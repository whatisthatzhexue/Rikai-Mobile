import '../../../core/models/agent/agent_tool.dart';
import '../ports/agent_capability_exception.dart';

const Set<String> _blockedKeyParts = <String>{
  'image_url',
  'input_image',
  'image_base64',
  'image_path',
  'image_file',
  'image_bytes',
  'base64',
  'file_path',
  'local_path',
  'content_uri',
};

const List<String> _blockedValueParts = <String>[
  'data:image',
  'base64,',
  'file://',
  'content://',
  '/sdcard/',
  'Android/data',
  '/storage/emulated',
  'C:\\',
  'c:\\',
];

/// Compile-time text-only DTOs are not enough; this runtime guard catches
/// accidental image/path leakage before a provider request leaves the device.
void assertNoImagePayload(Object? value, [String path = r'$']) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      for (final blocked in _blockedKeyParts) {
        if (key == blocked || key.contains(blocked)) {
          throw AgentCapabilityException(
            AgentToolErrorCode.invalidArguments,
            '请求包含不允许的图片或文件字段',
          );
        }
      }
      assertNoImagePayload(entry.value, '$path.${entry.key}');
    }
    return;
  }
  if (value is List) {
    for (var index = 0; index < value.length; index++) {
      assertNoImagePayload(value[index], '$path[$index]');
    }
    return;
  }
  if (value is String) {
    final lower = value.toLowerCase();
    for (final blocked in _blockedValueParts) {
      if (lower.contains(blocked)) {
        throw AgentCapabilityException(
          AgentToolErrorCode.invalidArguments,
          '请求包含不允许的图片或本地路径',
        );
      }
    }
  }
}

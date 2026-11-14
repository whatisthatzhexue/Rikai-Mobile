import 'package:image_picker/image_picker.dart';

/// Injectable image picker so the multi-image composer can be tested without
/// platform channels. Images stay on-device and are never sent to a provider.
abstract interface class AgentImagePicker {
  Future<List<String>> pickFromCamera();
  Future<List<String>> pickFromGallery();
}

class PlatformAgentImagePicker implements AgentImagePicker {
  PlatformAgentImagePicker([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<List<String>> pickFromCamera() async {
    final file = await _picker.pickImage(source: ImageSource.camera);
    return file == null ? const <String>[] : <String>[file.path];
  }

  @override
  Future<List<String>> pickFromGallery() async {
    final files = await _picker.pickMultiImage();
    return <String>[for (final file in files) file.path];
  }
}

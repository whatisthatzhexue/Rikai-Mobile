#ifndef FLUTTER_PLUGIN_MECAB_FOR_DART_PLUGIN_H_
#define FLUTTER_PLUGIN_MECAB_FOR_DART_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace mecab_for_dart {

class MecabForDartPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  MecabForDartPlugin();

  virtual ~MecabForDartPlugin();

  // Disallow copy and assign.
  MecabForDartPlugin(const MecabForDartPlugin&) = delete;
  MecabForDartPlugin& operator=(const MecabForDartPlugin&) = delete;

 private:
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace mecab_for_dart

#endif  // FLUTTER_PLUGIN_MECAB_FOR_DART_PLUGIN_H_

#include "include/mecab_for_dart/mecab_for_dart_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "mecab_for_dart_plugin.h"

void MecabForDartPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  mecab_for_dart::MecabForDartPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

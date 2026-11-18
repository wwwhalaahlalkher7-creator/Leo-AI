#include "leo_platform_capabilities/leo_platform_capabilities_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "leo_platform_capabilities/leo_platform_capabilities_plugin.h"

void LeoPlatformCapabilitiesPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  leo_platform_capabilities::LeoPlatformCapabilitiesPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

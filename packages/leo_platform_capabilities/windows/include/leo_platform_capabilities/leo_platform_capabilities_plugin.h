#ifndef FLUTTER_PLUGIN_LEO_PLATFORM_CAPABILITIES_PLUGIN_H_
#define FLUTTER_PLUGIN_LEO_PLATFORM_CAPABILITIES_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace leo_platform_capabilities {

class LeoPlatformCapabilitiesPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);
  explicit LeoPlatformCapabilitiesPlugin(flutter::BinaryMessenger* messenger);
  ~LeoPlatformCapabilitiesPlugin() override;

  LeoPlatformCapabilitiesPlugin(const LeoPlatformCapabilitiesPlugin&) = delete;
  LeoPlatformCapabilitiesPlugin& operator=(const LeoPlatformCapabilitiesPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

}  // namespace leo_platform_capabilities

#endif  // FLUTTER_PLUGIN_LEO_PLATFORM_CAPABILITIES_PLUGIN_H_

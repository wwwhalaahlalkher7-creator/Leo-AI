# This plugin is registered by Flutter's generated Windows plugin registrant.
add_library(leo_platform_capabilities_plugin STATIC
  "src/leo_platform_capabilities_plugin.cpp"
  "src/leo_platform_capabilities_plugin_c_api.cpp"
)
apply_standard_settings(leo_platform_capabilities_plugin)
set_target_properties(leo_platform_capabilities_plugin PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(leo_platform_capabilities_plugin PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(leo_platform_capabilities_plugin INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(leo_platform_capabilities_plugin PRIVATE flutter flutter_wrapper_plugin ole32 shell32 uuid bcrypt)

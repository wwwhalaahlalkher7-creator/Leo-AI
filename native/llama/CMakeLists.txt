cmake_minimum_required(VERSION 3.22)
project(leo_llama_backend LANGUAGES C CXX)

if(NOT DEFINED LLAMA_CPP_SOURCE_DIR OR NOT EXISTS "${LLAMA_CPP_SOURCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "LLAMA_CPP_SOURCE_DIR must point to the pinned llama.cpp source checkout")
endif()

# Build upstream components as static libraries and fold them into one
# platform-loadable Leo adapter. This avoids fragile upstream DLL/.so dependency
# chains while retaining the llama.cpp C API behind a stable Leo-owned ABI.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build upstream llama.cpp as static libraries" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(MSVC)
    # The native adapter exposes a C ABI only; no STL or CRT-owned allocation
    # crosses the DLL boundary. Static CRT avoids requiring the VC runtime to
    # be preinstalled on the user's Windows machine.
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>" CACHE STRING "" FORCE)
endif()
set(LLAMA_BUILD_IS_DEV OFF CACHE BOOL "Use the pinned upstream release version" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "Link the CPU backend into the runtime" FORCE)
set(GGML_CPU ON CACHE BOOL "Build the portable CPU backend" FORCE)
set(GGML_CPU_ALL_VARIANTS OFF CACHE BOOL "Avoid extra CPU backend variants" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "Avoid host-specific CPU instructions" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "Avoid an extra OpenMP runtime dependency" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "Disable the optional llamafile backend" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "Avoid an extra OpenSSL runtime dependency" FORCE)

add_subdirectory("${LLAMA_CPP_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/llama.cpp" EXCLUDE_FROM_ALL)

# The platform-loadable shared library is the only Leo-owned native library.
# llama.cpp and ggml are statically linked into it with PIC enabled above.
add_library(leo_llama_backend SHARED src/llama_probe.cpp)
target_compile_features(leo_llama_backend PRIVATE cxx_std_17)
target_include_directories(leo_llama_backend PRIVATE "${LLAMA_CPP_SOURCE_DIR}/include")
target_link_libraries(leo_llama_backend PRIVATE llama)
if(WIN32)
    target_link_libraries(leo_llama_backend PRIVATE Psapi)
    target_compile_options(leo_llama_backend PRIVATE /utf-8)
endif()
set_target_properties(leo_llama_backend PROPERTIES
    OUTPUT_NAME "leo_llama_backend"
    INSTALL_RPATH "$ORIGIN"
)

install(TARGETS leo_llama_backend LIBRARY DESTINATION lib RUNTIME DESTINATION bin)

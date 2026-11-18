$ErrorActionPreference = 'Stop'

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$LlamaSourceDir = if ($env:LLAMA_CPP_SOURCE_DIR) {
    (Resolve-Path $env:LLAMA_CPP_SOURCE_DIR).Path
} else {
    Join-Path $RootDir 'third_party/llama.cpp'
}
$ExpectedRevision = 'cd959bae99ff4bed22bef2604f45241c09bbb8c8'
$BuildDir = Join-Path $RootDir 'build/llama-windows-x64'
$OutputDir = Join-Path $RootDir 'build/windows-native/x64'

if (-not (Test-Path (Join-Path $LlamaSourceDir 'CMakeLists.txt'))) {
    throw "LLAMA_CPP_SOURCE_DIR must point to the pinned llama.cpp checkout: $LlamaSourceDir"
}
$ActualRevision = (& git -C $LlamaSourceDir rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to read llama.cpp revision.' }
if ($ActualRevision -ne $ExpectedRevision) {
    throw "llama.cpp revision mismatch. Expected $ExpectedRevision, found $ActualRevision"
}

$cmakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
if (-not $cmakeCommand) { throw 'CMake is required.' }

cmake -S (Join-Path $RootDir 'native/llama') `
    -B $BuildDir `
    -A x64 `
    -DCMAKE_BUILD_TYPE=Release `
    "-DLLAMA_CPP_SOURCE_DIR=$LlamaSourceDir" `
    -DBUILD_SHARED_LIBS=OFF `
    -DLLAMA_BUILD_IS_DEV=OFF `
    -DGGML_BACKEND_DL=OFF `
    -DGGML_CPU=ON `
    -DGGML_CPU_ALL_VARIANTS=OFF `
    -DGGML_NATIVE=OFF `
    -DGGML_OPENMP=OFF `
    -DGGML_LLAMAFILE=OFF `
    -DLLAMA_OPENSSL=OFF `
    -DLLAMA_BUILD_TESTS=OFF `
    -DLLAMA_BUILD_EXAMPLES=OFF `
    -DLLAMA_BUILD_SERVER=OFF `
    -DLLAMA_BUILD_COMMON=OFF `
    -DGGML_BUILD_TESTS=OFF `
    -DGGML_BUILD_EXAMPLES=OFF
if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed for the Windows native backend.' }

cmake --build $BuildDir --config Release --target leo_llama_backend --parallel
if ($LASTEXITCODE -ne 0) { throw 'Windows native backend compilation failed.' }

$Dll = Get-ChildItem -Path $BuildDir -Filter 'leo_llama_backend.dll' -Recurse -File |
    Select-Object -First 1
if (-not $Dll) { throw 'leo_llama_backend.dll was not produced.' }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
Copy-Item $Dll.FullName (Join-Path $OutputDir 'leo_llama_backend.dll') -Force

$DllPath = Join-Path $OutputDir 'leo_llama_backend.dll'
$Hash = (Get-FileHash $DllPath -Algorithm SHA256).Hash.ToLowerInvariant()
"$Hash  leo_llama_backend.dll" | Set-Content -Path (Join-Path $OutputDir 'SHA256SUMS.txt') -Encoding ascii

# Verify that the actual MSVC-built DLL can be loaded and exposes the complete
# stable Leo C ABI. This is a loader/export smoke test, not a model inference test.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LeoNativeDllSmoke {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryW(string path);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr module, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FreeLibrary(IntPtr module);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int InitDelegate();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr VersionDelegate();

    public static string Validate(string path) {
        IntPtr module = LoadLibraryW(path);
        if (module == IntPtr.Zero)
            throw new InvalidOperationException("LoadLibraryW failed: " + Marshal.GetLastWin32Error());
        try {
            string[] symbols = {
                "leo_llama_backend_init", "leo_llama_version", "leo_llama_load_model",
                "leo_llama_inference_available", "leo_llama_cancel_generation",
                "leo_llama_generate", "leo_llama_unload_model", "leo_llama_is_model_loaded",
                "leo_llama_loaded_context_tokens", "leo_llama_last_error",
                "leo_llama_memory_snapshot", "leo_llama_clear_context_memory"
            };
            foreach (string symbol in symbols) {
                if (GetProcAddress(module, symbol) == IntPtr.Zero)
                    throw new InvalidOperationException("Missing DLL export: " + symbol);
            }
            IntPtr initAddress = GetProcAddress(module, "leo_llama_backend_init");
            IntPtr versionAddress = GetProcAddress(module, "leo_llama_version");
            var init = (InitDelegate)Marshal.GetDelegateForFunctionPointer(initAddress, typeof(InitDelegate));
            var version = (VersionDelegate)Marshal.GetDelegateForFunctionPointer(versionAddress, typeof(VersionDelegate));
            if (init() != 1) throw new InvalidOperationException("llama.cpp backend initialization failed.");
            string versionText = Marshal.PtrToStringAnsi(version());
            if (String.IsNullOrWhiteSpace(versionText))
                throw new InvalidOperationException("llama.cpp returned an empty version string.");
            return versionText;
        } finally {
            FreeLibrary(module);
        }
    }
}
'@
$NativeVersion = [LeoNativeDllSmoke]::Validate($DllPath)
Write-Host "Windows native adapter smoke passed; llama.cpp version: $NativeVersion"
Write-Host "Windows x64 native backend built: $OutputDir"

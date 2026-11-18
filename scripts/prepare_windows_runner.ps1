$ErrorActionPreference = 'Stop'
# CMake 3.15+ enables CMP0091 behavior expected by audioplayers_windows.
$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$AppDir = Join-Path $RootDir 'apps/leo_app'
$RunnerCMake = Join-Path $AppDir 'windows/CMakeLists.txt'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter SDK is required to prepare the Windows runner.'
}

if (-not (Test-Path $RunnerCMake)) {
    Push-Location $AppDir
    try {
        flutter create --platforms=windows --org ai.leo --project-name leo_app --no-pub .
        if ($LASTEXITCODE -ne 0) { throw 'Flutter failed to generate the Windows runner.' }
    } finally {
        Pop-Location
    }
}

$Content = Get-Content -Raw -Path $RunnerCMake
$MinimumPattern = '(?m)^cmake_minimum_required\(VERSION\s+([0-9]+\.[0-9]+)\)'
$MinimumMatch = [regex]::Match($Content, $MinimumPattern)
if (-not $MinimumMatch.Success) { throw 'Windows CMakeLists.txt has no cmake_minimum_required declaration.' }
$MinimumVersion = [version]$MinimumMatch.Groups[1].Value
if ($MinimumVersion -lt [version]'3.15') {
    $Content = ([regex]::new($MinimumPattern)).Replace($Content, 'cmake_minimum_required(VERSION 3.15)', 1)
}

$PolicyPattern = '(?m)^cmake_policy\(VERSION\s+([0-9]+\.[0-9]+)\.\.\.([0-9]+\.[0-9]+)\)'
$PolicyMatch = [regex]::Match($Content, $PolicyPattern)
if ($PolicyMatch.Success) {
    if ([version]$PolicyMatch.Groups[1].Value -lt [version]'3.15') {
        $Content = ([regex]::new($PolicyPattern)).Replace($Content, 'cmake_policy(VERSION 3.15...$2)', 1)
    }
} else {
    $ProjectPattern = '(?m)^project\('
    if (-not [regex]::IsMatch($Content, $ProjectPattern)) {
        throw 'Windows CMakeLists.txt has no project() declaration for CMP0091 insertion.'
    }
    $Content = ([regex]::new($ProjectPattern)).Replace($Content, "cmake_policy(SET CMP0091 NEW)`r`nproject(", 1)
}

if ($Content -notmatch '(?m)^cmake_minimum_required\(VERSION\s+3\.1[5-9]' -or
    ($Content -notmatch '(?m)^cmake_policy\(VERSION\s+3\.1[5-9]\.\.\.' -and
     $Content -notmatch '(?m)^cmake_policy\(SET CMP0091 NEW\)')) {
    throw 'Unable to enforce CMake 3.15/CMP0091 compatibility for Windows dependencies.'
}
Set-Content -Path $RunnerCMake -Value $Content -Encoding utf8
Write-Host 'Windows runner prepared with CMake >= 3.15 for audioplayers_windows.'

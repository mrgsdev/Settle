<#
  Сборка установщика Settle для Windows.

    1. flutter build windows --release
    2. Inno Setup -> build\installer\Settle-Setup-<версия>.exe
    3. Портативная версия -> build\installer\Settle-Portable-<версия>.zip

  Запуск:
    powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1
    powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1 -SkipFlutterBuild

  Нужен Inno Setup 6.3+:  winget install JRSoftware.InnoSetup
#>
param(
  # Не пересобирать Flutter, взять готовый build\windows\x64\runner\Release.
  [switch]$SkipFlutterBuild
)

$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$release = Join-Path $root 'build\windows\x64\runner\Release'
$outDir = Join-Path $root 'build\installer'
$iss = Join-Path $PSScriptRoot 'settle.iss'
$exeName = 'Settle.exe'
$crtDlls = 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'

function Find-Iscc {
  $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $keys = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup *_is1',
          'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup *_is1',
          'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup *_is1'
  foreach ($key in $keys) {
    foreach ($item in (Get-ItemProperty $key -ErrorAction SilentlyContinue)) {
      if ($item.InstallLocation) {
        $exe = Join-Path $item.InstallLocation 'ISCC.exe'
        if (Test-Path $exe) { return $exe }
      }
    }
  }

  $dirs = "${env:ProgramFiles(x86)}", $env:ProgramFiles, "$env:LOCALAPPDATA\Programs"
  foreach ($dir in $dirs) {
    $exe = Get-ChildItem (Join-Path $dir 'Inno Setup*\ISCC.exe') -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($exe) { return $exe.FullName }
  }
  return $null
}

# Visual C++ runtime: из Visual Studio (Redist), иначе из системной папки.
function Find-CrtDir {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  if (Test-Path $vswhere) {
    $vs = & $vswhere -latest -products * -property installationPath
    if ($vs) {
      $crt = Get-ChildItem "$vs\VC\Redist\MSVC\*\x64\Microsoft.VC14*.CRT" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Parent.Parent.Name -match '^\d+(\.\d+)+$' } |
        Sort-Object { [version]$_.Parent.Parent.Name } -Descending |
        Select-Object -First 1
      if ($crt) { return $crt.FullName }
    }
  }
  # Из 32-битного PowerShell System32 перенаправляется в SysWOW64 (32-битные DLL).
  if ([Environment]::Is64BitProcess) { return "$env:SystemRoot\System32" }
  return "$env:SystemRoot\Sysnative"
}

# Версия из pubspec.yaml: "version: 1.2.3+4" -> 1.2.3
$match = Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(\d+\.\d+\.\d+)' |
  Select-Object -First 1
if (-not $match) { throw 'Не удалось прочитать version из pubspec.yaml' }
$version = $match.Matches[0].Groups[1].Value
$appInfo = Select-String -Path (Join-Path $root 'lib\app_info.dart') -Pattern "appVersion = '([^']+)'" |
  Select-Object -First 1
if (-not $appInfo -or $appInfo.Matches[0].Groups[1].Value -ne $version) {
  throw "Версия в lib\app_info.dart не совпадает с pubspec.yaml ($version) — исправьте appVersion"
}

$iscc = Find-Iscc
if (-not $iscc) {
  throw 'Не найден Inno Setup (ISCC.exe). Установите: winget install JRSoftware.InnoSetup'
}

if (-not $SkipFlutterBuild) {
  Write-Host "==> flutter build windows --release ($version)" -ForegroundColor Cyan
  Push-Location $root
  try {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build завершился с кодом $LASTEXITCODE" }
  } finally {
    Pop-Location
  }
}

if (-not (Test-Path (Join-Path $release $exeName))) {
  throw "Нет сборки в $release — запустите без -SkipFlutterBuild"
}
# Сборки под прежним названием оставляют в папке свой exe — он не должен попасть в пакет.
Get-ChildItem $release -Filter *.exe | Where-Object Name -ne $exeName | ForEach-Object {
  Write-Host "    Убираю устаревший $($_.Name)"
  Remove-Item $_.FullName -Force
}

$crtDir = Find-CrtDir
foreach ($dll in $crtDlls) {
  if (-not (Test-Path (Join-Path $crtDir $dll))) { throw "Нет $dll в $crtDir" }
}

Write-Host "==> Inno Setup: $iscc" -ForegroundColor Cyan
Write-Host "    Visual C++ runtime: $crtDir"
& $iscc /Qp "/DAppVersion=$version" "/DSourceDir=$release" "/DCrtDir=$crtDir" "/DOutputDir=$outDir" $iss
if ($LASTEXITCODE -ne 0) { throw "ISCC завершился с кодом $LASTEXITCODE" }

$setup = Join-Path $outDir "Settle-Setup-$version.exe"

# Портативная версия: та же сборка + Visual C++ runtime + portable.txt, который
# переключает приложение на хранение данных в UserData рядом с exe.
# Записи zip добавляются вручную: ZipFile.CreateFromDirectory в Windows PowerShell
# пишет пути через «\», и не все архиваторы их понимают.
$portableName = "Settle-Portable-$version"
$portableZip = Join-Path $outDir "$portableName.zip"
$note = @'
Портативная версия Settle.

Пока этот файл лежит рядом с Settle.exe, данные хранятся в папке UserData
рядом с программой — папку можно переносить на флешке или другой диск целиком.
Данные зашифрованы паролем, который задаётся при первом запуске.

Удалите этот файл, чтобы программа хранила данные в профиле пользователя Windows
(%APPDATA%\com.mrgsdev\Settle).
'@ -replace "`r?`n", "`r`n"

Write-Host "==> Портативная версия" -ForegroundColor Cyan
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
if (Test-Path $portableZip) { Remove-Item $portableZip -Force }
$zip = [IO.Compression.ZipFile]::Open($portableZip, 'Create')
try {
  $files = @(Get-ChildItem $release -Recurse -File -Exclude *.pdb, *.lib, *.exp, *.ilk |
    ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($release.Length + 1) } })
  $files += $crtDlls | ForEach-Object { @{ Path = (Join-Path $crtDir $_); Name = $_ } }
  foreach ($file in $files) {
    $name = "$portableName/" + $file.Name.Replace('\', '/')
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.Path, $name, 'Optimal')
  }
  $writer = New-Object IO.StreamWriter($zip.CreateEntry("$portableName/portable.txt").Open(), (New-Object Text.UTF8Encoding $true))
  try { $writer.Write($note) } finally { $writer.Dispose() }
} finally {
  $zip.Dispose()
}

Write-Host "==> Готово:" -ForegroundColor Green
Write-Host "    $setup"
Write-Host "    $portableZip"

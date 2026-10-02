@echo off
rem Builds the installer (double-click or run from a console). Arguments are passed through,
rem e.g.: installer\build.cmd -SkipFlutterBuild
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_installer.ps1" %*
if errorlevel 1 pause

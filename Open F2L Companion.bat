@echo off
rem Double-click to open Pip on Windows. Builds F2L the first time, and again whenever the code changes.
rem Mac equivalent: "Open F2L Companion.command".  Add --install-shortcut to put "F2L Companion" on the Desktop.
setlocal
set "ROOT=%~dp0"
set "PROJECT=%ROOT%Windows\F2L.Windows\F2L.Windows.csproj"
set "EXE=%ROOT%Windows\F2L.Windows\bin\Release\net10.0-windows10.0.19041.0\F2L.Windows.exe"

where dotnet >nul 2>nul
if errorlevel 1 (
  echo The .NET 10 SDK is needed to build F2L. Install it from https://dotnet.microsoft.com/download/dotnet/10.0 and run this again.
  pause
  exit /b 1
)

rem Already running: starting it again brings Pip's conversation up instead of rebuilding a file in use.
tasklist /fi "imagename eq F2L.Windows.exe" 2>nul | find /i "F2L.Windows.exe" >nul
if not errorlevel 1 (
  start "" "%EXE%"
  exit /b 0
)

echo Building F2L (quick when nothing changed)...
dotnet build "%PROJECT%" -c Release --nologo -v quiet
if errorlevel 1 (
  echo F2L did not build. See the messages above.
  pause
  exit /b 1
)

if /i "%~1"=="--install-shortcut" powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\install-shortcut-windows.ps1" -Target "%ROOT%Open F2L Companion.bat"

start "" "%EXE%"
endlocal

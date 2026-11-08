@echo off
rem Local Android debug build. One-time setup first: python -I tools\setup_android.py
rem Runs the tests, exports build\troop-debug.apk at low CPU priority, and installs it on a
rem USB-connected phone (USB debugging on) if one is plugged in. Pass "noinstall" to skip that.
setlocal
cd /d "%~dp0"
set "G=%~dp0..\_tools\godot\Godot_v4.7.2-stable_win64_console.exe"
set "JAVA_HOME=%~dp0..\_tools\jre-17"
set "PATH=%JAVA_HOME%\bin;%PATH%"
set "ADB=%~dp0..\_tools\android-sdk\platform-tools\adb.exe"
if not exist "%JAVA_HOME%\bin\java.exe" (echo Run setup first: python -I tools\setup_android.py & exit /b 1)
if not exist build mkdir build

echo [1/3] Tests
start "" /b /wait /belownormal "%G%" --headless --path . --script res://tests/run_tests.gd
if errorlevel 1 (echo Tests failed, no APK built. & exit /b 1)

echo [2/3] Export
if exist build\troop-debug.apk del build\troop-debug.apk
start "" /b /wait /belownormal "%G%" --headless --path . --export-debug "Android Debug" build/troop-debug.apk
if not exist build\troop-debug.apk (echo Export failed. & exit /b 1)
for %%A in (build\troop-debug.apk) do echo APK: %%~fA  (%%~zA bytes)

if /i "%~1"=="noinstall" exit /b 0
echo [3/3] Install
"%ADB%" get-state >nul 2>&1
if errorlevel 1 (echo No phone connected; copy the APK to the phone to install. & "%ADB%" kill-server >nul 2>&1 & exit /b 0)
"%ADB%" install -r build\troop-debug.apk
"%ADB%" kill-server >nul 2>&1

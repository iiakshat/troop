@echo off
rem Local Android debug build. One-time setup first: python -I tools\setup_android.py
rem Runs the tests, prepares the Gradle build template (tools\android_template.py: AdMob and
rem Firebase need a Gradle build), exports build\troop-debug.apk at low CPU priority, and installs
rem it on a USB-connected phone (USB debugging on) if one is plugged in. Pass "noinstall" to skip
rem that. The first Gradle build downloads Gradle and the Android libraries (a few hundred MB).
setlocal
cd /d "%~dp0"
set "TOOLS=%~dp0..\_tools"
rem From a git worktree (.claude\worktrees\x) the tools sit four folders up.
if not exist "%TOOLS%\godot" set "TOOLS=%~dp0..\..\..\..\_tools"
set "G=%TOOLS%\godot\Godot_v4.7.2-stable_win64_console.exe"
set "JAVA_HOME=%TOOLS%\jdk-17"
set "ANDROID_HOME=%TOOLS%\android-sdk"
set "ANDROID_SDK_ROOT=%TOOLS%\android-sdk"
set "PATH=%JAVA_HOME%\bin;%PATH%"
set "ADB=%TOOLS%\android-sdk\platform-tools\adb.exe"
if not exist "%JAVA_HOME%\bin\javac.exe" (echo Run setup first: python -I tools\setup_android.py & exit /b 1)
if not exist build mkdir build

echo [1/4] Tests
start "" /b /wait /belownormal "%G%" --headless --path . --script res://tests/run_tests.gd
if errorlevel 1 (echo Tests failed, no APK built. & exit /b 1)

echo [2/4] Gradle build template
python -I tools\android_template.py
if errorlevel 1 (echo Android build template failed. & exit /b 1)

echo [3/4] Export (Gradle)
if exist build\troop-debug.apk del build\troop-debug.apk
start "" /b /wait /belownormal "%G%" --headless --path . --export-debug "Android Debug" build/troop-debug.apk
if not exist build\troop-debug.apk (echo Export failed. & exit /b 1)
for %%A in (build\troop-debug.apk) do echo APK: %%~fA  (%%~zA bytes)

if /i "%~1"=="noinstall" exit /b 0
echo [4/4] Install
"%ADB%" get-state >nul 2>&1
if errorlevel 1 (echo No phone connected; copy the APK to the phone to install. & "%ADB%" kill-server >nul 2>&1 & exit /b 0)
"%ADB%" install -r build\troop-debug.apk
"%ADB%" kill-server >nul 2>&1

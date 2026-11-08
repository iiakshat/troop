@echo off
rem Play Troop on this PC (no Android needed). Arrow keys / A-D or mouse swipe to change lane,
rem S = shield, B = bomb. Add "-- lobby=1" to open the menu instead of jumping into level 1.
start "" "%~dp0..\_tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0." --resolution 540x960 %*

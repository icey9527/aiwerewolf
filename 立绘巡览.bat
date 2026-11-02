@echo off
setlocal
rem Default gallery settings. Edit values below, then double-click this file.
set "LAP=10"
rem Outer sweep is a full 360 degrees at the same angular speed as before (330 deg / 3 s).
set "OUTER_LAP=3.2727"
set "OUTER_HEIGHT=10"
set "OUTER_RADIUS=15"
set "OUTER_END_RADIUS=7"
set "RADIUS=2.10"
set "HEIGHT=2.40"
set "TARGET=2.20"
set "FOV=40"
set "FPS=0"
chcp 65001 >nul
cd /d "%~dp0"
if not "%~1"=="" goto arguments
"%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0game" --script res://checks/portrait_gallery.gd -- --fps=%FPS% --lap=%LAP% --outer-lap=%OUTER_LAP% --outer-height=%OUTER_HEIGHT% --outer-radius=%OUTER_RADIUS% --outer-end-radius=%OUTER_END_RADIUS% --radius=%RADIUS% --height=%HEIGHT% --target=%TARGET% --fov=%FOV%
goto end
:arguments
rem With arguments, forward all values unchanged, e.g. --seed=42 --lap=20.
"%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0game" --script res://checks/portrait_gallery.gd -- %*
:end
endlocal
7
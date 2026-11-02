@echo off
setlocal
cd /d "%~dp0"
"%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0game" --script res://checks/camera_console.gd

@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
where python >nul 2>nul
if errorlevel 1 (
    echo 未找到 Python，请先安装 Python 3.10 或更新版本。
    pause
    exit /b 1
)
set "ARGS=--scale 1 --columns 5"
if "%~1"=="" (
    python -X utf8 -I "%~dp0tools\art\portrait_preview.py" %ARGS%
) else (
    python -X utf8 -I "%~dp0tools\art\portrait_preview.py" "%~1" %ARGS%
)
if errorlevel 1 (
    echo 生成过程出现问题，请查看上方提示。
) else (
    echo 完成。结果位于 captures\portraits。
    explorer "%~dp0captures\portraits"
)
pause
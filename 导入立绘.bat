@echo off
setlocal
cd /d "%~dp0"
echo 正在扫描 art 目录并导入立绘...
python -X utf8 "%~dp0tools\art\import_characters.py"
if errorlevel 1 (
  echo.
  echo 导入失败：请确认已安装 Python，或把报错发给我。
)
echo.
pause

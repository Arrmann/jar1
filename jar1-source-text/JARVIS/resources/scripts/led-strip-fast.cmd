@echo off
setlocal
set "PYTHONIOENCODING=utf-8"
rem Prefer bundled TTS Python with bleak already installed (no pip on customer PCs).
set "PYTHONUSERBASE="
set "PY=%~dp0..\tts\runtime\python\pythonw.exe"
if not exist "%PY%" set "PY=%~dp0..\tts\runtime\python\python.exe"
if not exist "%PY%" set "PY=python"
if /I "%~1"=="scan" (
  "%PY%" "%~dp0led-strip-ble.py" scan --save --timeout 12
  exit /b %ERRORLEVEL%
)
"%PY%" "%~dp0led-strip-ble.py" %*
exit /b %ERRORLEVEL%

@echo off
setlocal
set "PYTHONIOENCODING=utf-8"
set "PYTHONUTF8=1"
set "PYTHONUSERBASE="
set "PY=%~dp0..\tts\runtime\python\pythonw.exe"
if not exist "%PY%" set "PY=%~dp0..\tts\runtime\python\python.exe"
if not exist "%PY%" set "PY=python"
"%PY%" "%~dp0tuya-plug.py" %*
exit /b %ERRORLEVEL%

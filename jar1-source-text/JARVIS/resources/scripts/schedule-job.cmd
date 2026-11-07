@echo off

setlocal

set "ROOT=%~dp0..\.."

set "ENGINE=%ROOT%\jarvis-app.exe"

set "PYTHONIOENCODING=utf-8"

set "PYTHONUSERBASE="

set "PY=%~dp0..\tts\runtime\python\pythonw.exe"
if not exist "%PY%" set "PY=%~dp0..\tts\runtime\python\python.exe"
if not exist "%PY%" set "PY=python"



if exist "%ENGINE%" (

  "%ENGINE%" --schedule %*

  set "RC=%ERRORLEVEL%"

  if not "%RC%"=="1" exit /b %RC%

  rem Old jarvis-app without shutdown subcommand — try Python below.

)



where py >nul 2>&1 && (

  py -3 "%~dp0schedule-job.py" %* 2>nul

  if not errorlevel 103 exit /b %ERRORLEVEL%

)

if not exist "%PY%" (

  echo [schedule-job] schedule failed and Python runtime missing 1>&2

  exit /b 1

)

"%PY%" "%~dp0schedule-job.py" %*

exit /b %ERRORLEVEL%


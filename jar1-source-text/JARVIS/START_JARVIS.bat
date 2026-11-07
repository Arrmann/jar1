@echo off
REM Avoid chcp 65001 -- on many Windows builds it breaks goto/call :labels in cmd.exe
setlocal EnableExtensions
title JARVIS

REM Commercial one-click launcher. Keep PowerShell lines free of IF () blocks with nested parens.
REM Resolve APP_DIR via PowerShell: prefer ASCII 8.3 when available (Cyrillic-safe),
REM otherwise keep the real Unicode long path. Never rely on cmd %CD% encoding alone.
cd /d "%~dp0"
set "APP_DIR=%CD%"
set "ERROR_DIR=%APPDATA%\com.jarvisn.assistant"
if not exist "%ERROR_DIR%" mkdir "%ERROR_DIR%" >nul 2>&1
set "ERROR_FILE=%ERROR_DIR%\JARVIS-STARTUP-ERROR.txt"
set "ENGINE_STDERR=%ERROR_DIR%\engine-stderr.log"
set "RESOLVE=%CD%\resources\scripts\resolve-app-dir.ps1"
set "PSHIDE=%CD%\resources\scripts\run-ps-hidden.exe"
set "APP_DIR_OUT=%TEMP%\jarvis-app-dir-%RANDOM%-%RANDOM%.txt"
del /q "%APP_DIR_OUT%" >nul 2>&1
if exist "%RESOLVE%" if exist "%PSHIDE%" "%PSHIDE%" "%RESOLVE%" -AppDir "%CD%" -OutFile "%APP_DIR_OUT%" >nul 2>&1
if exist "%RESOLVE%" if not exist "%PSHIDE%" powershell -NoProfile -NonInteractive -File "%RESOLVE%" -AppDir "%CD%" -OutFile "%APP_DIR_OUT%" >nul 2>&1
if exist "%APP_DIR_OUT%" set /p APP_DIR=<"%APP_DIR_OUT%"
del /q "%APP_DIR_OUT%" >nul 2>&1
if not defined APP_DIR set "APP_DIR=%CD%"
if not exist "%APP_DIR%\jarvis-app.exe" set "APP_DIR=%CD%"
cd /d "%APP_DIR%"
set "PSHIDE=%APP_DIR%\resources\scripts\run-ps-hidden.exe"
set "VC_REDIST=%APP_DIR%\vc_redist.x64.exe"
set "WEBVIEW2=%APP_DIR%\MicrosoftEdgeWebView2Setup.exe"
set "INSTALL_WV2=%APP_DIR%\resources\scripts\install-webview2.ps1"
set "FREE_IPC=%APP_DIR%\resources\scripts\free-jarvis-ipc.ps1"
set "HEALTHY=%APP_DIR%\resources\scripts\jarvis-ipc-healthy.ps1"
set "STARTING=%APP_DIR%\resources\scripts\jarvis-engine-starting.ps1"
set "SAME_TREE=%APP_DIR%\resources\scripts\jarvis-same-tree.ps1"
set "REFRESH_APPS=%APP_DIR%\resources\scripts\refresh-steam-app-shortcuts.ps1"
set "TTS_BOOT=%APP_DIR%\resources\scripts\tts-mode-boot.ps1"
set "REPAIR=%APP_DIR%\resources\scripts\repair-jarvis-runtime.ps1"
if not defined ProgramData set "ProgramData=C:\ProgramData"
set "RUNTIME_BACKUP=%ProgramData%\JARVIS\runtime-backup"
set "BACKUP_OK=0"
del /q "%ERROR_FILE%" >nul 2>&1

REM Explorer "open ZIP" leaves .zip as a path component. JARVIS cannot run from an archive.
set "APP_DIR_SLASH=%APP_DIR%\"
if /I not "%APP_DIR_SLASH%"=="%APP_DIR_SLASH:.zip\=%" goto from_zip

REM Self-heal missing runtime files / Cyrillic path / truncated Vosk before any hard checks.
REM StatusFile is UTF-8 without BOM - never capture PowerShell stdout via cmd redirect (UTF-16 trap).
set "JARVIS_VOSK_MODEL="
set "VOSK_OUT=%TEMP%\jarvis-vosk-model-%RANDOM%-%RANDOM%.txt"
del /q "%VOSK_OUT%" >nul 2>&1
if exist "%REPAIR%" "%PSHIDE%" "%REPAIR%" -AppDir "%APP_DIR%" -StatusFile "%VOSK_OUT%" >nul 2>&1
if exist "%VOSK_OUT%" findstr /b /c:"JARVIS_BACKUP_VALID=1" "%VOSK_OUT%" >nul 2>&1 && set "BACKUP_OK=1"
if exist "%VOSK_OUT%" for /f "usebackq tokens=1* delims==" %%A in (`findstr /b /c:"MODEL=" "%VOSK_OUT%"`) do set "JARVIS_VOSK_MODEL=%%B"
del /q "%VOSK_OUT%" >nul 2>&1
if "%BACKUP_OK%"=="1" set "JARVIS_RUNTIME_BACKUP=%RUNTIME_BACKUP%"
if "%BACKUP_OK%"=="1" if not exist "%APP_DIR%\libvosk.dll" set "PATH=%RUNTIME_BACKUP%;%PATH%"
if not defined JARVIS_VOSK_MODEL if "%BACKUP_OK%"=="1" if not exist "%APP_DIR%\resources\vosk\vosk-model-small-ru-0.22\am\final.mdl" set "JARVIS_VOSK_MODEL=%RUNTIME_BACKUP%\vosk-model-small-ru-0.22"

if not exist "%APP_DIR%\jarvis-app.exe" goto incomplete
if not exist "%APP_DIR%\jarvis-gui.exe" goto incomplete
if not exist "%APP_DIR%\libpv_recorder.dll" if "%BACKUP_OK%"=="0" goto incomplete
if not exist "%APP_DIR%\libvosk.dll" if "%BACKUP_OK%"=="0" goto incomplete
if not exist "%APP_DIR%\libgcc_s_seh-1.dll" if "%BACKUP_OK%"=="0" goto incomplete
if not exist "%APP_DIR%\libstdc++-6.dll" if "%BACKUP_OK%"=="0" goto incomplete
if not exist "%APP_DIR%\libwinpthread-1.dll" if "%BACKUP_OK%"=="0" goto incomplete
if not exist "%APP_DIR%\resources\vosk\vosk-model-small-ru-0.22\am\final.mdl" if "%BACKUP_OK%"=="0" goto incomplete
if not exist "%APP_DIR%\resources\rustpotter\jarvis-default.rpw" goto incomplete

if exist "%REFRESH_APPS%" "%PSHIDE%" "%REFRESH_APPS%" >nul 2>&1
if exist "%TTS_BOOT%" "%PSHIDE%" "%TTS_BOOT%" >nul 2>&1

REM --- IPC already healthy? ---
set "IPC_OK=0"
if exist "%HEALTHY%" if exist "%PSHIDE%" "%PSHIDE%" "%HEALTHY%" -ExpectedDir "%APP_DIR%" >nul 2>&1 && set "IPC_OK=1"
if exist "%HEALTHY%" if not exist "%PSHIDE%" powershell -NoProfile -NonInteractive -File "%HEALTHY%" -ExpectedDir "%APP_DIR%" >nul 2>&1 && set "IPC_OK=1"
if "%IPC_OK%"=="1" goto start_gui
if exist "%STARTING%" if exist "%PSHIDE%" "%PSHIDE%" "%STARTING%" >nul 2>&1 && goto start_gui
if exist "%STARTING%" if not exist "%PSHIDE%" powershell -NoProfile -NonInteractive -File "%STARTING%" >nul 2>&1 && goto start_gui

REM --- Reset and start engine ---
if exist "%FREE_IPC%" "%PSHIDE%" "%FREE_IPC%" >nul 2>&1
if not exist "%FREE_IPC%" taskkill /F /IM jarvis-app.exe >nul 2>&1
if not exist "%FREE_IPC%" taskkill /F /IM jarvis-run.exe >nul 2>&1
if not exist "%FREE_IPC%" taskkill /F /IM jarvis-gui.exe >nul 2>&1
if not exist "%FREE_IPC%" taskkill /F /IM jarvis-gestures.exe >nul 2>&1
del /q "%APPDATA%\com.jarvisn.assistant\ipc.port" >nul 2>&1 & del /q "%APPDATA%\com.priler.jarvis\ipc.port" >nul 2>&1
ping -n 2 127.0.0.1 >nul

REM Keep native loader / Rust startup errors even with a GUI-subsystem engine.
type nul > "%ENGINE_STDERR%"
start "" /min "%APP_DIR%\jarvis-app.exe" 2>> "%ENGINE_STDERR%"

set /a WAITED=0
:wait_ipc_1
set "IPC_OK=0"
if exist "%HEALTHY%" if exist "%PSHIDE%" "%PSHIDE%" "%HEALTHY%" -ExpectedDir "%APP_DIR%" >nul 2>&1 && set "IPC_OK=1"
if exist "%HEALTHY%" if not exist "%PSHIDE%" powershell -NoProfile -NonInteractive -File "%HEALTHY%" -ExpectedDir "%APP_DIR%" >nul 2>&1 && set "IPC_OK=1"
if "%IPC_OK%"=="1" goto start_gui
tasklist /FI "IMAGENAME eq jarvis-app.exe" 2>nul | find /I "jarvis-app.exe" >nul
if errorlevel 1 tasklist /FI "IMAGENAME eq jarvis-run.exe" 2>nul | find /I "jarvis-run.exe" >nul
if errorlevel 1 if %WAITED% GEQ 4 goto engine_retry
ping -n 2 127.0.0.1 >nul
set /a WAITED+=1
if %WAITED% LSS 50 goto wait_ipc_1

:engine_retry
if exist "%STARTING%" if exist "%PSHIDE%" "%PSHIDE%" "%STARTING%" >nul 2>&1 && goto start_gui
if exist "%STARTING%" if not exist "%PSHIDE%" powershell -NoProfile -NonInteractive -File "%STARTING%" >nul 2>&1 && goto start_gui
if exist "%FREE_IPC%" "%PSHIDE%" "%FREE_IPC%" >nul 2>&1
if not exist "%FREE_IPC%" taskkill /F /IM jarvis-app.exe >nul 2>&1
if not exist "%FREE_IPC%" taskkill /F /IM jarvis-run.exe >nul 2>&1
del /q "%APPDATA%\com.jarvisn.assistant\ipc.port" >nul 2>&1 & del /q "%APPDATA%\com.priler.jarvis\ipc.port" >nul 2>&1
ping -n 2 127.0.0.1 >nul
if exist "%VC_REDIST%" echo Installing Visual C++ runtime...
if exist "%VC_REDIST%" "%VC_REDIST%" /install /passive /norestart
REM Second chance: repair again then start
if exist "%REPAIR%" "%PSHIDE%" "%REPAIR%" -AppDir "%APP_DIR%" >nul 2>&1
start "" /min "%APP_DIR%\jarvis-app.exe" 2>> "%ENGINE_STDERR%"

set /a WAITED=0
:wait_ipc_2
set "IPC_OK=0"
if exist "%HEALTHY%" if exist "%PSHIDE%" "%PSHIDE%" "%HEALTHY%" -ExpectedDir "%APP_DIR%" >nul 2>&1 && set "IPC_OK=1"
if exist "%HEALTHY%" if not exist "%PSHIDE%" powershell -NoProfile -NonInteractive -File "%HEALTHY%" -ExpectedDir "%APP_DIR%" >nul 2>&1 && set "IPC_OK=1"
if "%IPC_OK%"=="1" goto start_gui
tasklist /FI "IMAGENAME eq jarvis-app.exe" 2>nul | find /I "jarvis-app.exe" >nul
if errorlevel 1 tasklist /FI "IMAGENAME eq jarvis-run.exe" 2>nul | find /I "jarvis-run.exe" >nul
if errorlevel 1 if %WAITED% GEQ 4 goto failed_engine
ping -n 2 127.0.0.1 >nul
set /a WAITED+=1
if %WAITED% LSS 55 goto wait_ipc_2
goto failed_engine

:start_gui
if exist "%SAME_TREE%" "%PSHIDE%" "%SAME_TREE%" -ExpectedDir "%APP_DIR%" -Check gui >nul 2>&1
if errorlevel 1 taskkill /F /IM jarvis-gui.exe >nul 2>&1
if exist "%SAME_TREE%" "%PSHIDE%" "%SAME_TREE%" -ExpectedDir "%APP_DIR%" -Check gui >nul 2>&1
if not errorlevel 1 exit /b 0
start "" "%APP_DIR%\jarvis-gui.exe"

set /a WAITED=0
:wait_gui_1
ping -n 2 127.0.0.1 >nul
tasklist /FI "IMAGENAME eq jarvis-gui.exe" 2>nul | find /I "jarvis-gui.exe" >nul
if not errorlevel 1 exit /b 0
set /a WAITED+=1
if %WAITED% LSS 20 goto wait_gui_1

if not exist "%WEBVIEW2%" if not exist "%INSTALL_WV2%" goto failed_gui
echo Installing WebView2...
if exist "%INSTALL_WV2%" if exist "%PSHIDE%" "%PSHIDE%" "%INSTALL_WV2%" -AppDir "%APP_DIR%" >nul 2>&1
if exist "%INSTALL_WV2%" if not exist "%PSHIDE%" powershell -NoProfile -NonInteractive -File "%INSTALL_WV2%" -AppDir "%APP_DIR%" >nul 2>&1
if not exist "%INSTALL_WV2%" if exist "%WEBVIEW2%" "%WEBVIEW2%" /silent /install
start "" "%APP_DIR%\jarvis-gui.exe"

set /a WAITED=0
:wait_gui_2
ping -n 2 127.0.0.1 >nul
tasklist /FI "IMAGENAME eq jarvis-gui.exe" 2>nul | find /I "jarvis-gui.exe" >nul
if not errorlevel 1 exit /b 0
set /a WAITED+=1
if %WAITED% LSS 35 goto wait_gui_2
goto failed_gui

:from_zip
> "%ERROR_FILE%" echo Do not run JARVIS from inside the ZIP archive.
>> "%ERROR_FILE%" echo.
>> "%ERROR_FILE%" echo Extract All to a normal folder (Desktop, Documents, or D:\JARVIS),
>> "%ERROR_FILE%" echo then start jarvis-launch.exe or START_JARVIS.bat from the extracted folder.
>> "%ERROR_FILE%" echo.
>> "%ERROR_FILE%" echo RU: Ne zapuskaj iz ZIP. Raspakuj (Izvlech vse) v obychnuyu papku, potom jarlyk.
start "" notepad.exe "%ERROR_FILE%"
exit /b 1

:incomplete
> "%ERROR_FILE%" echo JARVIS install is incomplete. Run JARVIS-Setup-1.0.5.exe again.
>> "%ERROR_FILE%" echo.
>> "%ERROR_FILE%" echo RU: Ustanovka nepolnaya. Zapusti Setup snova, potom jarlyk JARVIS.
>> "%ERROR_FILE%" echo Need: libvosk.dll + mingw DLLs + vosk model (am\final.mdl).
>> "%ERROR_FILE%" echo Prefer: C:\Program Files\JARVIS
>> "%ERROR_FILE%" echo Quarantine: Windows Security -^> Protection history -^> restore JARVIS files.
>> "%ERROR_FILE%" echo Log: %%APPDATA%%\com.jarvisn.assistant\log.txt
start "" notepad.exe "%ERROR_FILE%"
REM Still open the UI when possible so the customer is not stuck on a Notepad-only failure.
if exist "%APP_DIR%\jarvis-gui.exe" start "" "%APP_DIR%\jarvis-gui.exe"
exit /b 1

:failed_engine
> "%ERROR_FILE%" echo JARVIS voice engine exited or its local connection did not become ready.
>> "%ERROR_FILE%" echo.
>> "%ERROR_FILE%" echo This message alone does not identify the cause. Keep the evidence below for support.
>> "%ERROR_FILE%" echo Install folder: "%APP_DIR%"
>> "%ERROR_FILE%" echo Log: %%APPDATA%%\com.jarvisn.assistant\log.txt
>> "%ERROR_FILE%" echo Repair log: %%APPDATA%%\com.jarvisn.assistant\repair.log
>> "%ERROR_FILE%" echo.
>> "%ERROR_FILE%" echo --- Native engine error output ---
if exist "%ENGINE_STDERR%" type "%ENGINE_STDERR%" >> "%ERROR_FILE%"
>> "%ERROR_FILE%" echo.
>> "%ERROR_FILE%" echo --- Last startup stage ---
if exist "%ERROR_DIR%\engine-startup-stage.txt" type "%ERROR_DIR%\engine-startup-stage.txt" >> "%ERROR_FILE%"
>> "%ERROR_FILE%" echo.
>> "%ERROR_FILE%" echo --- Engine startup error ---
if exist "%ERROR_DIR%\engine-startup-error.txt" type "%ERROR_DIR%\engine-startup-error.txt" >> "%ERROR_FILE%"
>> "%ERROR_FILE%" echo.
>> "%ERROR_FILE%" echo --- GUI startup diagnostics, if available ---
if exist "%ERROR_DIR%\startup-fail.txt" type "%ERROR_DIR%\startup-fail.txt" >> "%ERROR_FILE%"
start "" notepad.exe "%ERROR_FILE%"
REM Keep UI available even when the voice engine dies (AV / path / mic).
if exist "%APP_DIR%\jarvis-gui.exe" start "" "%APP_DIR%\jarvis-gui.exe"
exit /b 1

:failed_gui
> "%ERROR_FILE%" echo JARVIS interface failed to start.
>> "%ERROR_FILE%" echo.
>> "%ERROR_FILE%" echo SmartScreen: More info -^> Run anyway
>> "%ERROR_FILE%" echo Or: right-click START_JARVIS.bat -^> Properties -^> Unblock -^> OK
>> "%ERROR_FILE%" echo WebView2 is required; Setup installs the Microsoft bootstrapper (needs internet once if missing).
>> "%ERROR_FILE%" echo.
>> "%ERROR_FILE%" echo RU: SmartScreen -^> Podrobnee -^> Vypolnit v lyubom sluchae. Ili razblokiruj fajl.
start "" notepad.exe "%ERROR_FILE%"
exit /b 1


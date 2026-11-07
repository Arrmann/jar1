$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$Python = ".venv\Scripts\python.exe"
if (-not (Test-Path $Python)) {
    throw "Сначала выполни .\install.ps1"
}

& $Python -m pip install --upgrade pyinstaller
if ($LASTEXITCODE -ne 0) { throw "Не удалось установить PyInstaller." }

& $Python -m PyInstaller --noconfirm --clean --noconsole --onefile --name JARVIS `
  --hidden-import=pynput.keyboard._win32 `
  --hidden-import=pynput.mouse._win32 `
  --hidden-import=pyttsx3.drivers `
  --hidden-import=pyttsx3.drivers.sapi5 `
  --hidden-import=faster_whisper `
  --hidden-import=pygame `
  --collect-submodules pyttsx3 `
  --collect-all faster_whisper `
  --collect-all PySide6 `
  --collect-all edge_tts `
  --collect-all pygame `
  --collect-all sounddevice `
  --add-data "resources;resources" `
  --add-data "integration;integration" `
  main.py

if ($LASTEXITCODE -ne 0) { throw "PyInstaller завершился с ошибкой." }
Write-Host "Сборка завершена: dist\JARVIS.exe" -ForegroundColor Green

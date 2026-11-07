$ErrorActionPreference = "Stop"

if (Test-Path ".venv\Scripts\Activate.ps1") {
    & .venv\Scripts\Activate.ps1
} else {
    Write-Host "Сначала выполни .\install.ps1" -ForegroundColor Red
    exit 1
}

pip install pyinstaller

pyinstaller --noconsole --onefile --name AURA `
  --hidden-import=pynput.keyboard._win32 `
  --hidden-import=pynput.mouse._win32 `
  --hidden-import=pyttsx3.drivers `
  --hidden-import=pyttsx3.drivers.sapi5 `
  --hidden-import=faster_whisper `
  --collect-submodules pyttsx3 `
  --collect-all faster_whisper `
  --collect-all PySide6 `
  --collect-all edge_tts `
  main.py

Write-Host "Сборка завершена: dist\AURA.exe" -ForegroundColor Green

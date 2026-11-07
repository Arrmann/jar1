$ErrorActionPreference = "Stop"

Write-Host "AURA AI: установка окружения..." -ForegroundColor Cyan

if (-not (Test-Path ".venv")) {
    python -m venv .venv
}

& .venv\Scripts\Activate.ps1

python -m pip install --upgrade pip
pip install -r requirements.txt

Write-Host ""
Write-Host "Установка завершена." -ForegroundColor Green
Write-Host "Запуск: .\run.ps1" -ForegroundColor Cyan
Write-Host "Сборка EXE: .\build.ps1" -ForegroundColor Cyan

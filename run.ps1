$ErrorActionPreference = "Stop"

if (Test-Path ".venv\Scripts\Activate.ps1") {
    & .venv\Scripts\Activate.ps1
} else {
    Write-Host "Сначала выполни .\install.ps1" -ForegroundColor Red
    exit 1
}

python main.py

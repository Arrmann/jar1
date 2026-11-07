$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "JARVIS Assistant: установка окружения..." -ForegroundColor Cyan

$Python = $null
if (Test-Path ".venv\Scripts\python.exe") {
    $Python = (Resolve-Path ".venv\Scripts\python.exe").Path
} else {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { $Python = $cmd.Source }
}

if (-not $Python) {
    throw "Python не найден. Запустите Setup.exe или установите Python 3.13/3.14 x64."
}

$pyVersion = & $Python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
if ($pyVersion -notin @("3.13", "3.14")) {
    throw "Требуется Python 3.13 или 3.14 x64; обнаружен Python $pyVersion."
}

if (-not (Test-Path ".venv\Scripts\python.exe")) {
    & $Python -m venv .venv
    if ($LASTEXITCODE -ne 0) { throw "Не удалось создать виртуальное окружение." }
}
$Python = (Resolve-Path ".venv\Scripts\python.exe").Path

Write-Host "[1/4] Обновление pip" -ForegroundColor Cyan
& $Python -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "Не удалось обновить pip." }

Write-Host "[2/4] Удаление старого pygame, если установлен" -ForegroundColor Cyan
& $Python -m pip uninstall -y pygame

Write-Host "[3/4] Установка pygame-ce из готового wheel" -ForegroundColor Cyan
& $Python -m pip install --only-binary=:all: pygame-ce==2.5.8
if ($LASTEXITCODE -ne 0) { throw "Не удалось установить pygame-ce wheel. Компилятор Visual Studio не требуется." }

Write-Host "[4/4] Установка библиотек JARVIS" -ForegroundColor Cyan
& $Python -m pip install -r requirements.txt
if ($LASTEXITCODE -ne 0) { throw "Не удалось установить зависимости. Проверьте вывод pip выше." }

& $Python -c "import PySide6, faster_whisper, pygame, PIL; print('Runtime check: OK')"
if ($LASTEXITCODE -ne 0) { throw "Проверка импортов не пройдена." }

Write-Host ""
Write-Host "Установка завершена." -ForegroundColor Green
Write-Host "Запуск: .\run.ps1" -ForegroundColor Cyan
Write-Host "Сборка EXE: .\build.ps1" -ForegroundColor Cyan

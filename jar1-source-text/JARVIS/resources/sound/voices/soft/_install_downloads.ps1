$ErrorActionPreference = "Stop"
$src = "C:\Users\Мирослав\Downloads"
$dst = "C:\jarvisTOP\resources\sound\voices\soft\ru"
New-Item -ItemType Directory -Force -Path $dst | Out-Null

# Map unique substring in download name -> target stem(s)
# Prefer exact unique tags from Fish filenames.
$map = @(
    @{ Match = "Слушаю-тебя! (1)"; Dest = @("reply1") },
    @{ Match = "Да,-я-тут!"; Dest = @("reply2") },
    @{ Match = "Я-здесь!"; Dest = @("reply3") },
    @{ Match = "Готова-помочь!"; Dest = @("reply5") },
    @{ Match = "Готово!"; Dest = @("ok1") },
    @{ Match = "Сделано!"; Dest = @("ok2") },
    @{ Match = "Хорошо!"; Dest = @("ok3") },
    @{ Match = "Конечно!"; Dest = @("ok4") },
    @{ Match = "Пожалуйста!"; Dest = @("thanks1") },
    @{ Match = "Не-за-что!"; Dest = @("thanks2") },
    @{ Match = "Рада-помочь!"; Dest = @("thanks3") },
    @{ Match = "Пока!"; Dest = @("goodbye1") },
    @{ Match = "До-связи!"; Dest = @("goodbye2") },
    @{ Match = "Хорошего-дня!"; Dest = @("goodbye3") },
    @{ Match = "Время-вышло!"; Dest = @("timer_done", "timer_done1") },
    @{ Match = "Таймер-сработал!"; Dest = @("timer_done2") },
    @{ Match = "Привет,-рада-слышать!"; Dest = @("hello2") },
    @{ Match = "(smiling,-friendly,-warm)-Привет!"; Dest = @("hello1", "hello3", "greet1") },
    @{ Match = "Всё-хорошо,-а-у-тебя-к"; Dest = @("howare1") },
    @{ Match = "Отлично,-слушаю-тебя!"; Dest = @("howare2") },
    @{ Match = "Хорошо!-Чем-помочь"; Dest = @("howare3") },
    @{ Match = "Доброе-утро!"; Dest = @("greet_morning") },
    @{ Match = "Добрый-день!"; Dest = @("greet_day") },
    @{ Match = "Добрый-вечер!"; Dest = @("greet_evening") },
    @{ Match = "Доброй-ночи!"; Dest = @("greet_night") }
)

$files = Get-ChildItem -LiteralPath $src -Filter "Спокойный-2026-10-17*.mp3"
$used = @{}
$copied = @()

foreach ($rule in $map) {
    $hit = $files | Where-Object { $_.Name -like "*$($rule.Match)*" } | Select-Object -First 1
    if (-not $hit) {
        Write-Host "MISSING source: $($rule.Match)"
        continue
    }
    foreach ($stem in $rule.Dest) {
        $out = Join-Path $dst "$stem.mp3"
        Copy-Item -LiteralPath $hit.FullName -Destination $out -Force
        $copied += $stem
        Write-Host "OK $stem <- $($hit.Name)"
    }
    $used[$hit.FullName] = $true
}

# Fallbacks for missing variants (reuse closest)
$fb = @{
    "reply4" = "reply2"          # no Да-да? yet
    "ok5" = "ok4"                # no Есть!
    "timer_done3" = "timer_done1"
}
foreach ($k in $fb.Keys) {
    $target = Join-Path $dst "$k.mp3"
    $from = Join-Path $dst "$($fb[$k]).mp3"
    if (-not (Test-Path -LiteralPath $target) -and (Test-Path -LiteralPath $from)) {
        Copy-Item -LiteralPath $from -Destination $target -Force
        Write-Host "FALLBACK $k <- $($fb[$k])"
        $copied += $k
    }
}

$expected = @(
    "reply1","reply2","reply3","reply4","reply5",
    "ok1","ok2","ok3","ok4","ok5",
    "thanks1","thanks2","thanks3",
    "goodbye1","goodbye2","goodbye3",
    "timer_done","timer_done1","timer_done2","timer_done3",
    "hello1","hello2","hello3",
    "howare1","howare2","howare3",
    "greet1","greet_morning","greet_day","greet_evening","greet_night"
)
Write-Host "----"
$missing = @()
foreach ($e in $expected) {
    if (-not (Test-Path (Join-Path $dst "$e.mp3"))) { $missing += $e }
}
Write-Host "Present reactions: $((Get-ChildItem $dst -Filter '*.mp3' | Where-Object { $_.Name -notlike 'cmd_*' }).Count)"
if ($missing.Count) { Write-Host "STILL MISSING: $($missing -join ', ')" } else { Write-Host "All reaction slots filled" }

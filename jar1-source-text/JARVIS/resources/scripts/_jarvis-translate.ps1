# Pure translate helpers (no UI). Dot-source from translate-hud.ps1 and tools/test-translate.ps1.
# ASCII-only source (WinPS 5.1 safe).

function Resolve-JarvisTranslatePair {
    param(
        [string]$Text,
        [ValidateSet("auto", "ru", "en")]
        [string]$Target = "auto"
    )
    $hasCyr = $Text -match "\p{IsCyrillic}"
    switch ($Target) {
        "ru" {
            if ($hasCyr) { return "ru|ru" }
            return "en|ru"
        }
        "en" {
            if ($hasCyr) { return "ru|en" }
            return "en|en"
        }
        default {
            if ($hasCyr) { return "ru|en" }
            return "en|ru"
        }
    }
}

function Get-JarvisTranslateTargetCode {
    param([string]$Pair)
    $parts = $Pair.Split("|")
    if ($parts.Count -ge 2) { return $parts[1] }
    return "ru"
}

function Get-JarvisTranslateTargetName {
    param([string]$Code)
    switch (($Code | ForEach-Object { $_.ToLowerInvariant() })) {
        "ru" { return "Russian" }
        "en" { return "English" }
        default { return "Russian" }
    }
}

function Get-JarvisTranslateSystemPrompt {
    param([string]$TargetName)
    return ("You are a precise translator. Translate the user text into {0}. " +
            "Output ONLY the translation. No quotes, no markdown, no labels, no explanations, no notes.") -f $TargetName
}

function Clean-JarvisTranslationResult {
    param([AllowNull()][string]$Raw)
    if ($null -eq $Raw) { return "" }
    $s = [string]$Raw
    $s = $s -replace "`r`n", "`n" -replace "`r", "`n"
    $s = $s.Trim()
    # Strip wrapping quotes the model sometimes adds.
    if (($s.StartsWith('"') -and $s.EndsWith('"')) -or ($s.StartsWith("'") -and $s.EndsWith("'"))) {
        if ($s.Length -ge 2) { $s = $s.Substring(1, $s.Length - 2).Trim() }
    }
    # Drop fenced code blocks if the model wraps the answer.
    $fence = [string]([char]96) + [char]96 + [char]96
    if ($s.StartsWith($fence)) {
        $s = $s.Substring($fence.Length)
        if ($s -match '^[a-zA-Z0-9_-]+\r?\n') {
            $s = $s -replace '^[a-zA-Z0-9_-]+\r?\n', ''
        }
        $idx = $s.LastIndexOf($fence)
        if ($idx -ge 0) { $s = $s.Substring(0, $idx) }
        $s = $s.Trim()
    }
    # Common preface lines (ASCII + UTF-8 "Perevod").
    $prefRu = [Text.Encoding]::UTF8.GetString([byte[]](0xD0,0x9F,0xD0,0xB5,0xD1,0x80,0xD0,0xB5,0xD0,0xB2,0xD0,0xBE,0xD0,0xB4))
    $s = $s -replace ("^(Translation|Translated|{0})\s*:\s*" -f [regex]::Escape($prefRu)), ''
    return $s.Trim()
}

function Invoke-JarvisTranslateText {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [ValidateSet("auto", "ru", "en")]
        [string]$Target = "auto",
        [int]$MaxChars = 2500
    )

    $src = ([string]$Text).Trim()
    if ([string]::IsNullOrWhiteSpace($src)) {
        return @{ Ok = $false; Text = ""; Pair = ""; Error = "EMPTY_SRC"; Skipped = $false }
    }
    if ($src.Length -gt $MaxChars) {
        $src = $src.Substring(0, $MaxChars)
    }

    $pair = Resolve-JarvisTranslatePair -Text $src -Target $Target
    if ($pair -eq "ru|ru" -or $pair -eq "en|en") {
        return @{ Ok = $true; Text = $src; Pair = $pair; Error = ""; Skipped = $true }
    }

    $code = Get-JarvisTranslateTargetCode -Pair $pair
    $name = Get-JarvisTranslateTargetName -Code $code
    $system = Get-JarvisTranslateSystemPrompt -TargetName $name

    if (-not (Get-Command Invoke-JarvisLlmChat -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot "_jarvis-llm.ps1")
    }

    $maxTok = [Math]::Min(2000, [Math]::Max(120, [int]($src.Length * 1.4) + 64))
    $resp = Invoke-JarvisLlmChat -System $system -User $src -Temperature 0.15 -MaxTokens $maxTok -TimeoutSec 50
    if (-not $resp.Ok) {
        return @{ Ok = $false; Text = ""; Pair = $pair; Error = $resp.Error; Skipped = $false }
    }
    $clean = Clean-JarvisTranslationResult $resp.Text
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return @{ Ok = $false; Text = ""; Pair = $pair; Error = "EMPTY"; Skipped = $false }
    }
    return @{ Ok = $true; Text = $clean; Pair = $pair; Error = ""; Skipped = $false }
}

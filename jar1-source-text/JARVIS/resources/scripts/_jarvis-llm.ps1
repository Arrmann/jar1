# Shared OpenAI-compatible chat for PowerShell HUD scripts.
# Reads app.db (same as Rust settings), unseals JARVISDP1: DPAPI blobs, posts /chat/completions.
# ASCII-only source (WinPS 5.1 safe).

. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")

function Get-JarvisLlmSettingsPath {
    return (Join-Path (Get-JarvisDataDir) "app.db")
}

function Ensure-JarvisDpapi {
    if ("JarvisDpapi1" -as [type]) { return }
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class JarvisDpapi1 {
  [StructLayout(LayoutKind.Sequential)]
  public struct DATA_BLOB {
    public int cbData;
    public IntPtr pbData;
  }
  [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  public static extern bool CryptUnprotectData(
    ref DATA_BLOB pDataIn, IntPtr ppszDataDescr, IntPtr pOptionalEntropy,
    IntPtr pvReserved, IntPtr pPromptStruct, int dwFlags, out DATA_BLOB pDataOut);
  [DllImport("kernel32.dll")]
  public static extern IntPtr LocalFree(IntPtr hMem);

  static byte[] FromHex(string hex) {
    if (string.IsNullOrEmpty(hex) || (hex.Length % 2) != 0) return null;
    var buf = new byte[hex.Length / 2];
    for (int i = 0; i < buf.Length; i++) {
      buf[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
    }
    return buf;
  }

  public static string UnprotectJarvis(string value) {
    if (string.IsNullOrEmpty(value)) return "";
    const string prefix = "JARVISDP1:";
    if (!value.StartsWith(prefix, StringComparison.Ordinal)) return value;
    var raw = FromHex(value.Substring(prefix.Length));
    if (raw == null || raw.Length == 0) throw new Exception("DPAPI blob: bad hex");
    var handle = GCHandle.Alloc(raw, GCHandleType.Pinned);
    try {
      var input = new DATA_BLOB { cbData = raw.Length, pbData = handle.AddrOfPinnedObject() };
      DATA_BLOB output;
      if (!CryptUnprotectData(ref input, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 0, out output)) {
        throw new Exception("DPAPI CryptUnprotectData failed (wrong user/PC?)");
      }
      try {
        var bytes = new byte[output.cbData];
        Marshal.Copy(output.pbData, bytes, 0, output.cbData);
        return Encoding.UTF8.GetString(bytes);
      } finally {
        if (output.pbData != IntPtr.Zero) LocalFree(output.pbData);
      }
    } finally {
      handle.Free();
    }
  }
}
"@
}

function Unprotect-JarvisSecret([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $v = $Value.Trim()
    if (-not $v.StartsWith("JARVISDP1:")) { return $v }
    Ensure-JarvisDpapi
    return [JarvisDpapi1]::UnprotectJarvis($v)
}

function Get-JarvisLlmConfig {
    $path = Get-JarvisLlmSettingsPath
    $cfg = @{
        ApiKey   = ""
        Model    = "inclusionai/ling-3.0-tiny:free"
        BaseUrl  = "https://openrouter.ai/api/v1"
        Provider = ""
        Ok       = $false
        Error    = ""
    }
    if (-not (Test-Path -LiteralPath $path)) {
        $cfg.Error = "NO_SETTINGS"
        return $cfg
    }
    try {
        $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($json.api_keys -and $json.api_keys.openai) {
            $cfg.ApiKey = Unprotect-JarvisSecret ([string]$json.api_keys.openai)
        }
        if ($json.llm_model) { $cfg.Model = ([string]$json.llm_model).Trim() }
        if ($json.llm_base_url) { $cfg.BaseUrl = ([string]$json.llm_base_url).Trim().TrimEnd("/") }
        if ($json.llm_provider) { $cfg.Provider = ([string]$json.llm_provider).Trim() }
    } catch {
        $cfg.Error = "BAD_SETTINGS"
        return $cfg
    }
    if ([string]::IsNullOrWhiteSpace($cfg.ApiKey)) {
        $cfg.Error = "NO_KEY"
        return $cfg
    }
    if ($cfg.ApiKey.StartsWith("JARVISDP1:")) {
        $cfg.Error = "KEY_SEALED"
        $cfg.ApiKey = ""
        return $cfg
    }
    $cfg.Ok = $true
    return $cfg
}

function Resolve-JarvisLlmEndpoint {
    param(
        [string]$ApiKey,
        [string]$BaseUrl
    )
    $key = ($ApiKey | ForEach-Object { $_.Trim() })
    $base = ($BaseUrl | ForEach-Object { $_.Trim().TrimEnd("/") })
    $lowKey = $key.ToLowerInvariant()
    $lowBase = $base.ToLowerInvariant()

    $isOr = $lowBase -match "openrouter\.ai"
    $isDs = $lowBase -match "api\.deepseek\.com"
    $isGem = $lowBase -match "generativelanguage\.googleapis\.com"
    $isOai = $lowBase -match "api\.openai\.com"
    $custom = ($base -ne "") -and (-not $isOr) -and (-not $isDs) -and (-not $isGem) -and (-not $isOai)

    if ($custom) {
        return @{ Base = $base; Url = "$base/chat/completions" }
    }

    if ($lowKey.StartsWith("sk-or-")) {
        if ([string]::IsNullOrWhiteSpace($base) -or $isDs -or $isGem -or $isOai) {
            $base = "https://openrouter.ai/api/v1"
        }
    } elseif ($key.StartsWith("AIza") -or $lowKey.StartsWith("aiza")) {
        if ([string]::IsNullOrWhiteSpace($base) -or $isOr -or $isDs -or $isOai) {
            $base = "https://generativelanguage.googleapis.com/v1beta/openai"
        }
    } elseif ($lowKey.StartsWith("sk-proj-")) {
        if ([string]::IsNullOrWhiteSpace($base) -or $isOr -or $isDs -or $isGem) {
            $base = "https://api.openai.com/v1"
        }
    } elseif ($lowKey.StartsWith("sk-")) {
        if ([string]::IsNullOrWhiteSpace($base) -or $isOr -or $isGem) {
            $base = "https://api.deepseek.com"
        }
    } elseif ([string]::IsNullOrWhiteSpace($base)) {
        $base = "https://openrouter.ai/api/v1"
    }

    return @{ Base = $base; Url = "$base/chat/completions" }
}

function Resolve-JarvisLlmModel {
    param(
        [string]$Model,
        [string]$Base,
        [string]$ApiKey
    )
    $m = ($Model | ForEach-Object { $_.Trim() })
    $lowBase = $Base.ToLowerInvariant()
    $isDs = $lowBase -match "api\.deepseek\.com"
    $isOr = $lowBase -match "openrouter\.ai"
    $isGem = $lowBase -match "generativelanguage\.googleapis\.com"

    if (-not [string]::IsNullOrWhiteSpace($m)) {
        if ($isDs) {
            $lower = $m.ToLowerInvariant()
            if ($lower.Contains("reasoner")) { return "deepseek-reasoner" }
            if ($lower.Contains("flash")) { return "deepseek-flash" }
            if ($m.Contains("/") -or $m.Contains(":") -or $lower.Contains("deepseek")) {
                return "deepseek-chat"
            }
        }
        return $m
    }
    if ($isOr) { return "inclusionai/ling-3.0-tiny:free" }
    if ($isGem -or $ApiKey.StartsWith("AIza")) { return "gemini-2.0-flash" }
    return "deepseek-chat"
}

function Escape-JarvisJsonString([string]$s) {
    if ($null -eq $s) { return "" }
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $code = [int][char]$ch
        switch ($ch) {
            '"' { [void]$sb.Append('\"'); continue }
            '\' { [void]$sb.Append('\\'); continue }
            "`n" { [void]$sb.Append('\n'); continue }
            "`r" { [void]$sb.Append('\r'); continue }
            "`t" { [void]$sb.Append('\t'); continue }
        }
        if ($code -lt 32) {
            [void]$sb.Append(('\u{0:x4}' -f $code))
            continue
        }
        [void]$sb.Append($ch)
    }
    return $sb.ToString()
}

function Invoke-JarvisLlmChat {
    param(
        [Parameter(Mandatory = $true)][string]$System,
        [Parameter(Mandatory = $true)][string]$User,
        [double]$Temperature = 0.2,
        [int]$MaxTokens = 1200,
        [int]$TimeoutSec = 45
    )

    $cfg = Get-JarvisLlmConfig
    if (-not $cfg.Ok) {
        return @{ Ok = $false; Text = ""; Error = $cfg.Error }
    }

    $ep = Resolve-JarvisLlmEndpoint -ApiKey $cfg.ApiKey -BaseUrl $cfg.BaseUrl
    $model = Resolve-JarvisLlmModel -Model $cfg.Model -Base $ep.Base -ApiKey $cfg.ApiKey
    $isOr = $ep.Base.ToLowerInvariant() -match "openrouter\.ai"

    $sysEsc = Escape-JarvisJsonString $System
    $userEsc = Escape-JarvisJsonString $User
    $modelEsc = Escape-JarvisJsonString $model
    $tempInv = $Temperature.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $body = "{`"model`":`"$modelEsc`",`"temperature`":$tempInv,`"max_tokens`":$MaxTokens,`"messages`":[{`"role`":`"system`",`"content`":`"$sysEsc`"},{`"role`":`"user`",`"content`":`"$userEsc`"}]}"

    try {
        # TLS 1.2 for older WinPS hosts.
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

        $headers = @{
            Authorization = "Bearer $($cfg.ApiKey)"
            "User-Agent"  = "JARVIS/1.0 (Windows; Translate)"
        }
        if ($isOr) {
            $headers["HTTP-Referer"] = "https://openrouter.ai/"
            $headers["X-Title"] = "JARVIS"
        }

        $resp = Invoke-RestMethod -Uri $ep.Url -Method Post -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType "application/json; charset=utf-8" -TimeoutSec $TimeoutSec
        $text = ""
        if ($resp.choices -and $resp.choices.Count -gt 0) {
            $msg = $resp.choices[0].message
            if ($null -ne $msg.content) { $text = [string]$msg.content }
        }
        if ([string]::IsNullOrWhiteSpace($text) -and $resp.error) {
            $errMsg = if ($resp.error.message) { [string]$resp.error.message } else { [string]$resp.error }
            return @{ Ok = $false; Text = ""; Error = $errMsg }
        }
        if ([string]::IsNullOrWhiteSpace($text)) {
            return @{ Ok = $false; Text = ""; Error = "EMPTY" }
        }
        return @{ Ok = $true; Text = $text; Error = "" }
    } catch {
        $msg = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $msg = [string]$_.ErrorDetails.Message
        }
        return @{ Ok = $false; Text = ""; Error = $msg }
    }
}

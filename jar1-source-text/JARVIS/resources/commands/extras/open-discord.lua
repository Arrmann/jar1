-- Prefer the installed Squirrel launcher; fall back to web app.
jarvis.system.exec("powershell", {
  "-NoProfile",
  "-ExecutionPolicy",
  "Bypass",
  "-Command",
  "$u = Join-Path $env:LOCALAPPDATA 'Discord\\Update.exe'; " ..
  "$d = Join-Path $env:LOCALAPPDATA 'Discord\\Discord.exe'; " ..
  "if (Test-Path -LiteralPath $u) { Start-Process -FilePath $u -ArgumentList '--processStart','Discord.exe' | Out-Null; exit 0 }; " ..
  "if (Test-Path -LiteralPath $d) { Start-Process -FilePath $d | Out-Null; exit 0 }; " ..
  "& 'resources/scripts/open-url.ps1' 'https://discord.com/app'",
})
return { chain = false }

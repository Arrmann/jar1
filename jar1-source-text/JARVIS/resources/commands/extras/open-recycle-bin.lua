-- Open recycle bin; don't block voice on settle.
jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-Command",
  "& { . 'resources/scripts/_jarvis-last-target.ps1'; Initialize-JarvisLastTarget; Start-Process explorer.exe 'shell:RecycleBinFolder'; Start-Sleep -Milliseconds 200; $hints=@('Recycle Bin','Корзина'); $h=[JarvisLastTarget]::FindExplorerByKeywords([string[]]$hints,$true); if($h -eq [IntPtr]::Zero){$h=[JarvisLastTarget]::FindTopExplorerFolder($true)}; if($h -ne [IntPtr]::Zero){ Save-JarvisLastTarget -Hwnd $h -Process 'explorer' -Title ([JarvisLastTarget]::TitleOf($h)) -Url 'shell:RecycleBinFolder' -Keywords $hints -Kind 'explorer' } }",
})
return { chain = false }

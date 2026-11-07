-- Always open Telegram in the browser (WebK / Web A).
jarvis.system.exec("powershell", {
  "-NoProfile",
  "-WindowStyle",
  "Hidden",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "resources/scripts/open-url.ps1",
  "https://web.telegram.org/k/",
})
return { chain = false }

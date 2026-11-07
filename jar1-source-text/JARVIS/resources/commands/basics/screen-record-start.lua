jarvis.system.exec("powershell", {
  "-NoProfile",
  "-WindowStyle",
  "Hidden",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "resources/scripts/screen-record.ps1",
  "-Action",
  "start",
})
jarvis.system.notify("Запись экрана", "REC сверху · F12 или «останови запись»")
return { chain = false }

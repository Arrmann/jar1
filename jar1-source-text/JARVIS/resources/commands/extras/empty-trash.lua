jarvis.system.exec("powershell", {"-NoProfile","-Command","Clear-RecycleBin -Force -ErrorAction SilentlyContinue"})
return { chain = false }

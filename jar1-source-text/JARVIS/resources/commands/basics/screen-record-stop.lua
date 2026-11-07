local result = jarvis.system.exec_wait("powershell", {
  "-NoProfile",
  "-WindowStyle",
  "Hidden",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "resources/scripts/screen-record.ps1",
  "-Action",
  "stop",
})
local out = tostring(result.stdout or "")
if out:find("OK:", 1, true) then
  return { chain = false, silent = false }
end
return { chain = false, silent = true }

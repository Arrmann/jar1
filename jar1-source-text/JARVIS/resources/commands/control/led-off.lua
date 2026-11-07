-- Turn the BLE LED strip off via bundled Python (no cmd.exe flash).
jarvis.system.run_python("resources/scripts/led-strip-ble.py", { "off" })
return { chain = false }

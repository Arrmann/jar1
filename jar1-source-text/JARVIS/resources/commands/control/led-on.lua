-- Turn the BLE LED strip on via bundled Python (no cmd.exe flash).
jarvis.system.run_python("resources/scripts/led-strip-ble.py", { "on" })
return { chain = false }

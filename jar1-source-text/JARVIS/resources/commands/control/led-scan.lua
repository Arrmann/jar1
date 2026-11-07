-- Find / reconnect the BLE LED strip (ELK-BLEDOM / Lotus). Uses the warm daemon.
jarvis.system.run_python("resources/scripts/led-strip-ble.py", {
  "scan", "--save", "--timeout", "12",
})
return { chain = false }

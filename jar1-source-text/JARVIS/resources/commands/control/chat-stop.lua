-- End continuous Neurochat conversation («закончи чат»).
jarvis.neurochat.session(false)
jarvis.system.notify("Нейрочат", "Нейрочат выключен — снова обычные команды")
return { chain = false, silent = true }

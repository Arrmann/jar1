-- Start continuous Neurochat conversation («чат»).
-- Hard path in jarvis-app usually handles this first; this is a fuzzy-match fallback.
jarvis.neurochat.session(true)
jarvis.system.notify("Нейрочат", "Слушаю без «джарвис». Вопрос — говори сразу. Выход: «закончи чат»")
return { chain = true, silent = true }

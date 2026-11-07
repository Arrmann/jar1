if not jarvis.system.media_session("next", jarvis.context.phrase or "") then
  error("Не найден активный плеер. Сначала включи музыку или видео.")
end
return { chain = false, silent = true }

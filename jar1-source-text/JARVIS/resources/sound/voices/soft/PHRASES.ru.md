# Soft — дружелюбный скрипт + разметка Fish Audio

Голос: милый, тёплый, **живой человек**. Без нудятины и без «подруги/романтики».
Продукт — **JARVIS**. Файлы → `soft/ru/` с точными именами.

## Как генерить в Fish (обязательно)

1. Модель: **Fish Audio Drama 3** (или новее).
2. Скорость: **1.05–1.1×** (не 1.0 — иначе плоская).
3. В поле текста вставляй **целиком колонку «Fish»** — со скобками.
4. Делай 2–3 дубля, бери самый тёплый.
5. Не озвучивай одно слово без эмо-тега — будет «нудная бабенция».

Примеры тегов: `(smiling, friendly, warm)`, `(cheerful, friendly)`, `(curious, friendly)`.

---

## A. Реакции (вариативность)

| файл | что слышно | **вставь в Fish как есть** |
|------|------------|---------------------------|
| `reply1.mp3` | Слушаю тебя | `(smiling, friendly, warm) Слушаю тебя!` |
| `reply2.mp3` | Да, я тут | `(smiling, friendly) Да, я тут!` |
| `reply3.mp3` | Я здесь | `(friendly, warm) Я здесь!` |
| `reply4.mp3` | Да-да? | `(curious, friendly, smiling) Да-да?` |
| `reply5.mp3` | Готова помочь | `(smiling, eager, friendly) Готова помочь!` |
| `ok1.mp3` | Готово | `(smiling, friendly, satisfied) Готово!` |
| `ok2.mp3` | Сделано | `(smiling, friendly) Сделано!` |
| `ok3.mp3` | Хорошо | `(warm, friendly) Хорошо!` |
| `ok4.mp3` | Конечно | `(smiling, friendly) Конечно!` |
| `ok5.mp3` | Есть | `(cheerful, friendly) Есть!` |
| `thanks1.mp3` | Пожалуйста | `(smiling, warm) Пожалуйста!` |
| `thanks2.mp3` | Не за что | `(friendly, warm) Не за что!` |
| `thanks3.mp3` | Рада помочь | `(smiling, friendly) Рада помочь!` |
| `goodbye1.mp3` | Пока | `(smiling, warm) Пока!` |
| `goodbye2.mp3` | До связи | `(friendly, warm) До связи!` |
| `goodbye3.mp3` | Хорошего дня | `(smiling, friendly, warm) Хорошего дня!` |
| `timer_done.mp3` | Время вышло | `(friendly, clear) Время вышло!` |
| `timer_done1.mp3` | Время вышло | `(friendly, clear) Время вышло!` |
| `timer_done2.mp3` | Таймер сработал | `(friendly, soft alert) Таймер сработал!` |
| `timer_done3.mp3` | Напоминаю тебе | `(warm, friendly) Напоминаю тебе!` |
| `hello1.mp3` | Привет | `(smiling, friendly, warm) Привет!` |
| `hello2.mp3` | Привет, рада слышать | `(smiling, friendly) Привет, рада слышать!` |
| `hello3.mp3` | Привет | `(cheerful, friendly) Привет!` |
| `howare1.mp3` | Всё хорошо, а у тебя как? | `(smiling, friendly, warm) Всё хорошо, а у тебя как?` |
| `howare2.mp3` | Отлично, слушаю тебя | `(cheerful, friendly) Отлично, слушаю тебя!` |
| `howare3.mp3` | Хорошо! Чем помочь? | `(smiling, eager, friendly) Хорошо! Чем помочь?` |
| `greet1.mp3` | Привет | `(smiling, friendly, warm) Привет!` |
| `greet_morning.mp3` | Доброе утро | `(smiling, soft, warm) Доброе утро!` |
| `greet_day.mp3` | Добрый день | `(friendly, warm) Добрый день!` |
| `greet_evening.mp3` | Добрый вечер | `(warm, friendly) Добрый вечер!` |
| `greet_night.mp3` | Доброй ночи | `(soft, warm, gentle) Доброй ночи!` |

### Блоки для копипаста в Fish (реакции)

```
(smiling, friendly, warm) Слушаю тебя!
(smiling, friendly) Да, я тут!
(friendly, warm) Я здесь!
(curious, friendly, smiling) Да-да?
(smiling, eager, friendly) Готова помочь!
(smiling, friendly, satisfied) Готово!
(smiling, friendly) Сделано!
(warm, friendly) Хорошо!
(smiling, friendly) Конечно!
(cheerful, friendly) Есть!
(smiling, warm) Пожалуйста!
(friendly, warm) Не за что!
(smiling, friendly) Рада помочь!
(smiling, warm) Пока!
(friendly, warm) До связи!
(smiling, friendly, warm) Хорошего дня!
(friendly, clear) Время вышло!
(friendly, clear) Время вышло!
(friendly, soft alert) Таймер сработал!
(warm, friendly) Напоминаю тебе!
(smiling, friendly, warm) Привет!
(smiling, friendly) Привет, рада слышать!
(cheerful, friendly) Привет!
(smiling, friendly, warm) Всё хорошо, а у тебя как?
(cheerful, friendly) Отлично, слушаю тебя!
(smiling, eager, friendly) Хорошо! Чем помочь?
(smiling, friendly, warm) Привет!
(smiling, soft, warm) Доброе утро!
(friendly, warm) Добрый день!
(warm, friendly) Добрый вечер!
(soft, warm, gentle) Доброй ночи!
```

---

## B. Команды `cmd_*` — **132** файлов (как у Миты)

Короткие тёплые подтверждения. В Fish — всегда с тегом.

| файл | что слышно | **Fish** | фраза вызова (подсказка) |
|------|------------|----------|--------------------------|
| `cmd_brightness_down.mp3` | Сделала потемнее | `(smiling, friendly, warm) Сделала потемнее!` | экран темнее |
| `cmd_brightness_up.mp3` | Сделала поярче | `(smiling, friendly, warm) Сделала поярче!` | экран ярче |
| `cmd_browser_back.mp3` | Вернула назад | `(smiling, friendly, warm) Вернула назад!` | назад |
| `cmd_browser_close_tab.mp3` | Закрыла вкладку | `(smiling, friendly, warm) Закрыла вкладку!` | закрой вкладку |
| `cmd_browser_downloads.mp3` | Открыла загрузки | `(smiling, friendly, warm) Открыла загрузки!` | открой загрузки браузера |
| `cmd_browser_incognito.mp3` | Открыла инкогнито | `(smiling, friendly, warm) Открыла инкогнито!` | инкогнито |
| `cmd_browser_new_tab.mp3` | Открыла новую вкладку | `(smiling, friendly, warm) Открыла новую вкладку!` | новая вкладка |
| `cmd_browser_next_tab.mp3` | Перешла на следующую | `(smiling, friendly, warm) Перешла на следующую!` | следующая вкладка |
| `cmd_browser_open.mp3` | Открыла браузер | `(smiling, friendly, warm) Открыла браузер!` | открой браузер |
| `cmd_browser_prev_tab.mp3` | Вернула прошлую вкладку | `(smiling, friendly, warm) Вернула прошлую вкладку!` | вкладка влево |
| `cmd_browser_refresh.mp3` | Обновила | `(smiling, friendly, warm) Обновила!` | обнови страницу |
| `cmd_browser_reopen_tab.mp3` | Вернула вкладку | `(smiling, friendly, warm) Вернула вкладку!` | верни вкладку |
| `cmd_cancel_shutdown.mp3` | Отменила выключение | `(smiling, friendly, warm) Отменила выключение!` | отмени выключение |
| `cmd_clipboard_history.mp3` | Открыла буфер | `(smiling, friendly, warm) Открыла буфер!` | открой буфер обмена |
| `cmd_close_active.mp3` | Закрыла | `(smiling, friendly, warm) Закрыла!` | закрой |
| `cmd_dictate.mp3` | Диктуй, я слушаю | `(smiling, friendly, warm) Диктуй, я слушаю!` | запиши |
| `cmd_empty_trash.mp3` | Очистила корзину | `(smiling, friendly, warm) Очистила корзину!` | очисти корзину |
| `cmd_game_mode.mp3` | Включила игровой режим | `(smiling, friendly, warm) Включила игровой режим!` |  |
| `cmd_gestures_off.mp3` | Выключила жесты | `(smiling, friendly, warm) Выключила жесты!` | выключи жесты |
| `cmd_gestures_on.mp3` | Включила жесты | `(smiling, friendly, warm) Включила жесты!` | управление жестами |
| `cmd_input_copy.mp3` | Скопировала | `(smiling, friendly, warm) Скопировала!` | скопируй |
| `cmd_input_cut.mp3` | Вырезала | `(smiling, friendly, warm) Вырезала!` | вырежи |
| `cmd_input_find.mp3` | Открыла поиск | `(smiling, friendly, warm) Открыла поиск!` | найди на странице |
| `cmd_input_new_doc.mp3` | Сделала новый документ | `(smiling, friendly, warm) Сделала новый документ!` | новый документ |
| `cmd_input_paste.mp3` | Вставила | `(smiling, friendly, warm) Вставила!` | вставь |
| `cmd_input_print.mp3` | Отправила на печать | `(smiling, friendly, warm) Отправила на печать!` | напечатай документ |
| `cmd_input_redo.mp3` | Вернула как было | `(smiling, friendly, warm) Вернула как было!` | повтори |
| `cmd_input_save.mp3` | Сохранила | `(smiling, friendly, warm) Сохранила!` | сохрани |
| `cmd_input_select_all.mp3` | Выделила всё | `(smiling, friendly, warm) Выделила всё!` | выдели всё |
| `cmd_input_switch_lang.mp3` | Переключила язык | `(smiling, friendly, warm) Переключила язык!` | смени язык |
| `cmd_input_undo.mp3` | Отменила | `(smiling, friendly, warm) Отменила!` | верни назад |
| `cmd_lock_pc.mp3` | Заблокировала | `(smiling, friendly, warm) Заблокировала!` | заблокируй компьютер |
| `cmd_maximize_window.mp3` | Развернула на весь экран | `(smiling, friendly, warm) Развернула на весь экран!` | разверни окно |
| `cmd_media_next.mp3` | Включила следующий | `(smiling, friendly, warm) Включила следующий!` | следующий трек |
| `cmd_media_play_pause.mp3` | Поставила на паузу | `(smiling, friendly, warm) Поставила на паузу!` | пауза |
| `cmd_media_prev.mp3` | Вернула прошлый трек | `(smiling, friendly, warm) Вернула прошлый трек!` | предыдущий трек |
| `cmd_media_stop.mp3` | Остановила | `(smiling, friendly, warm) Остановила!` | останови медиа |
| `cmd_minimize_all.mp3` | Всё свернула | `(smiling, friendly, warm) Всё свернула!` | сверни все |
| `cmd_minimize_window.mp3` | Свернула | `(smiling, friendly, warm) Свернула!` | сверни |
| `cmd_open_about_pc.mp3` | Открыла про компьютер | `(smiling, friendly, warm) Открыла про компьютер!` | информация о компьютере |
| `cmd_open_avito.mp3` | Открыла Авито | `(smiling, friendly, warm) Открыла Авито!` | открой авито |
| `cmd_open_bluetooth.mp3` | Открыла блютуз | `(smiling, friendly, warm) Открыла блютуз!` | открой блютуз |
| `cmd_open_calculator.mp3` | Открыла калькулятор | `(smiling, friendly, warm) Открыла калькулятор!` | открой калькулятор |
| `cmd_open_calendar.mp3` | Открыла календарь | `(smiling, friendly, warm) Открыла календарь!` | календарь |
| `cmd_open_camera.mp3` | Открыла камеру | `(smiling, friendly, warm) Открыла камеру!` | запусти камеру |
| `cmd_open_chatgpt.mp3` | Открыла Чатджипити | `(smiling, friendly, warm) Открыла Чатджипити!` | открой chatgpt |
| `cmd_open_claude.mp3` | Открыла Клода | `(smiling, friendly, warm) Открыла Клода!` | открой claude |
| `cmd_open_cursor.mp3` | Открыла Курсор | `(smiling, friendly, warm) Открыла Курсор!` | открой курсор |
| `cmd_open_deepseek.mp3` | Открыла Дипсик | `(smiling, friendly, warm) Открыла Дипсик!` | deep seek |
| `cmd_open_desktop_folder.mp3` | Открыла рабочий стол | `(smiling, friendly, warm) Открыла рабочий стол!` | открой десктоп |
| `cmd_open_discord.mp3` | Открыла Дискорд | `(smiling, friendly, warm) Открыла Дискорд!` | открой дискорд |
| `cmd_open_display_settings.mp3` | Открыла настройки экрана | `(smiling, friendly, warm) Открыла настройки экрана!` | настройки дисплея |
| `cmd_open_documents.mp3` | Открыла документы | `(smiling, friendly, warm) Открыла документы!` | открой документы |
| `cmd_open_downloads.mp3` | Открыла загрузки | `(smiling, friendly, warm) Открыла загрузки!` | открой загрузки |
| `cmd_open_emoji_panel.mp3` | Открыла эмодзи | `(smiling, friendly, warm) Открыла эмодзи!` | win точка |
| `cmd_open_excel.mp3` | Открыла Эксель | `(smiling, friendly, warm) Открыла Эксель!` | microsoft excel |
| `cmd_open_explorer.mp3` | Открыла проводник | `(smiling, friendly, warm) Открыла проводник!` | открой проводник |
| `cmd_open_gemini.mp3` | Открыла Джемини | `(smiling, friendly, warm) Открыла Джемини!` | google gemini |
| `cmd_open_github.mp3` | Открыла Гитхаб | `(smiling, friendly, warm) Открыла Гитхаб!` | открой гитхаб |
| `cmd_open_gmail.mp3` | Открыла почту | `(smiling, friendly, warm) Открыла почту!` | открой почту |
| `cmd_open_google_drive.mp3` | Открыла Гугл диск | `(smiling, friendly, warm) Открыла Гугл диск!` | google drive |
| `cmd_open_instagram.mp3` | Открыла Инстаграм | `(smiling, friendly, warm) Открыла Инстаграм!` | открой инстаграм |
| `cmd_open_ivi.mp3` | Открыла Иви | `(smiling, friendly, warm) Открыла Иви!` | открой иви |
| `cmd_open_kinopoisk.mp3` | Открыла Кинопоиск | `(smiling, friendly, warm) Открыла Кинопоиск!` | кино поиск |
| `cmd_open_maps.mp3` | Открыла карты | `(smiling, friendly, warm) Открыла карты!` | открой карты |
| `cmd_open_meet.mp3` | Открыла Мит | `(smiling, friendly, warm) Открыла Мит!` | google meet |
| `cmd_open_netflix.mp3` | Открыла Нетфликс | `(smiling, friendly, warm) Открыла Нетфликс!` | открой нетфликс |
| `cmd_open_news.mp3` | Открыла новости | `(smiling, friendly, warm) Открыла новости!` | новости |
| `cmd_open_night_light.mp3` | Включила ночной свет | `(smiling, friendly, warm) Включила ночной свет!` | включи ночной свет |
| `cmd_open_notepad.mp3` | Открыла блокнот | `(smiling, friendly, warm) Открыла блокнот!` | открой блокнот |
| `cmd_open_notion.mp3` | Открыла Ноушен | `(smiling, friendly, warm) Открыла Ноушен!` | открой ноушен |
| `cmd_open_obs.mp3` | Открыла ОБС | `(smiling, friendly, warm) Открыла ОБС!` | открой обс |
| `cmd_open_ozon.mp3` | Открыла Озон | `(smiling, friendly, warm) Открыла Озон!` | открой озон |
| `cmd_open_paint.mp3` | Открыла Пейнт | `(smiling, friendly, warm) Открыла Пейнт!` | открой пейнт |
| `cmd_open_photos.mp3` | Открыла фото | `(smiling, friendly, warm) Открыла фото!` | галерея |
| `cmd_open_pinterest.mp3` | Открыла Пинтерест | `(smiling, friendly, warm) Открыла Пинтерест!` | открой pinterest |
| `cmd_open_powerpoint.mp3` | Открыла презентацию | `(smiling, friendly, warm) Открыла презентацию!` | powerpoint |
| `cmd_open_recycle_bin.mp3` | Открыла корзину | `(smiling, friendly, warm) Открыла корзину!` | открой корзину |
| `cmd_open_rutube.mp3` | Открыла Рутуб | `(smiling, friendly, warm) Открыла Рутуб!` | открой рутуб / открой рот / рот убы |
| `cmd_open_screenshots_folder.mp3` | Открыла скриншоты | `(smiling, friendly, warm) Открыла скриншоты!` | мои скриншоты |
| `cmd_open_settings.mp3` | Открыла параметры | `(smiling, friendly, warm) Открыла параметры!` | открой параметры |
| `cmd_open_snip.mp3` | Открыла ножницы | `(smiling, friendly, warm) Открыла ножницы!` | фрагмент экрана |
| `cmd_open_sound_settings.mp3` | Открыла звук | `(smiling, friendly, warm) Открыла звук!` | настройки звука |
| `cmd_open_startup_apps.mp3` | Открыла автозагрузку | `(smiling, friendly, warm) Открыла автозагрузку!` | программы при включении |
| `cmd_open_steam.mp3` | Открыла Стим | `(smiling, friendly, warm) Открыла Стим!` | открой стим |
| `cmd_open_storage.mp3` | Открыла память | `(smiling, friendly, warm) Открыла память!` | открой хранилище |
| `cmd_open_task_manager.mp3` | Открыла диспетчер | `(smiling, friendly, warm) Открыла диспетчер!` | открой диспетчер задач |
| `cmd_open_teams.mp3` | Открыла Тимс | `(smiling, friendly, warm) Открыла Тимс!` | teams |
| `cmd_open_telegram.mp3` | Открыла Телеграм | `(smiling, friendly, warm) Открыла Телеграм!` | открой телеграм |
| `cmd_open_terminal.mp3` | Открыла терминал | `(smiling, friendly, warm) Открыла терминал!` | открой терминал |
| `cmd_open_tiktok.mp3` | Открыла Тикток | `(smiling, friendly, warm) Открыла Тикток!` | открой тикток |
| `cmd_open_translate.mp3` | Открыла переводчик | `(smiling, friendly, warm) Открыла переводчик!` | открой переводчик гугл |
| `cmd_open_twitch.mp3` | Открыла Твич | `(smiling, friendly, warm) Открыла Твич!` | открой твич |
| `cmd_open_update.mp3` | Открыла обновления | `(smiling, friendly, warm) Открыла обновления!` | обновление виндоус |
| `cmd_open_vk.mp3` | Открыла Вконтакте | `(smiling, friendly, warm) Открыла Вконтакте!` | открой вконтакте |
| `cmd_open_weather.mp3` | Открыла погоду | `(smiling, friendly, warm) Открыла погоду!` | какая погода |
| `cmd_open_whatsapp.mp3` | Открыла Ватсап | `(smiling, friendly, warm) Открыла Ватсап!` | открой ватсап |
| `cmd_open_wifi.mp3` | Открыла вайфай | `(smiling, friendly, warm) Открыла вайфай!` | открой вайфай |
| `cmd_open_wildberries.mp3` | Открыла Вайлдберриз | `(smiling, friendly, warm) Открыла Вайлдберриз!` | wildberries |
| `cmd_open_word.mp3` | Открыла Ворд | `(smiling, friendly, warm) Открыла Ворд!` | microsoft word |
| `cmd_open_yandex.mp3` | Открыла Яндекс | `(smiling, friendly, warm) Открыла Яндекс!` | открой ya.ru |
| `cmd_open_yandex_disk.mp3` | Открыла Яндекс диск | `(smiling, friendly, warm) Открыла Яндекс диск!` | открой яндекс диск |
| `cmd_open_yandex_maps.mp3` | Открыла Яндекс карты | `(smiling, friendly, warm) Открыла Яндекс карты!` | открой яндекс карты |
| `cmd_open_yandex_music.mp3` | Открыла Яндекс музыку | `(smiling, friendly, warm) Открыла Яндекс музыку!` |  |
| `cmd_open_youtube.mp3` | Открыла Ютуб | `(smiling, friendly, warm) Открыла Ютуб!` | открой ютуб |
| `cmd_open_youtube_music.mp3` | Открыла Ютуб музыку | `(smiling, friendly, warm) Открыла Ютуб музыку!` |  |
| `cmd_open_zoom.mp3` | Открыла Зум | `(smiling, friendly, warm) Открыла Зум!` | открой зум |
| `cmd_reload_explorer.mp3` | Перезапустила проводник | `(smiling, friendly, warm) Перезапустила проводник!` | перезапуск explorer |
| `cmd_remind.mp3` | Хорошо, напомню | `(smiling, friendly, warm) Хорошо, напомню!` | напомни мне |
| `cmd_remind_cancel.mp3` | Убрала напоминание | `(smiling, friendly, warm) Убрала напоминание!` | отмени напоминания |
| `cmd_restart_pc.mp3` | Перезагружаю | `(smiling, friendly, warm) Перезагружаю!` | перезагрузи компьютер |
| `cmd_screenshot.mp3` | Сделала скриншот | `(smiling, friendly, warm) Сделала скриншот!` | сделай скриншот |
| `cmd_search_google.mp3` | Ищу в Гугле | `(smiling, friendly, warm) Ищу в Гугле!` | найди |
| `cmd_search_wiki.mp3` | Открыла Википедию | `(smiling, friendly, warm) Открыла Википедию!` | википедия |
| `cmd_search_yandex.mp3` | Ищу в Яндексе | `(smiling, friendly, warm) Ищу в Яндексе!` | найди в яндексе |
| `cmd_search_youtube.mp3` | Ищу на Ютубе | `(smiling, friendly, warm) Ищу на Ютубе!` | найди на ютубе |
| `cmd_show_desktop.mp3` | Показала рабочий стол | `(smiling, friendly, warm) Показала рабочий стол!` | покажи рабочий стол |
| `cmd_shutdown_pc.mp3` | Выключаю | `(smiling, friendly, warm) Выключаю!` | выключи компьютер |
| `cmd_sleep_pc.mp3` | Усыпляю компьютер | `(smiling, friendly, warm) Усыпляю компьютер!` | спящий режим |
| `cmd_speak.mp3` | Читаю | `(smiling, friendly, warm) Читаю!` |  |
| `cmd_speak_stop.mp3` | Хорошо, остановила | `(smiling, friendly, warm) Хорошо, остановила!` | останови печать |
| `cmd_switch_window.mp3` | Переключила окно | `(smiling, friendly, warm) Переключила окно!` | переключи окно |
| `cmd_timer_set.mp3` | Поставила таймер | `(smiling, friendly, warm) Поставила таймер!` | таймер на |
| `cmd_translate.mp3` | Открыла переводчик | `(smiling, friendly, warm) Открыла переводчик!` | переведи на русский |
| `cmd_use_browser_chrome.mp3` | Поставила Хром | `(smiling, friendly, warm) Поставила Хром!` | браузер chrome |
| `cmd_use_browser_yandex.mp3` | Поставила Яндекс браузер | `(smiling, friendly, warm) Поставила Яндекс браузер!` | браузер яндекс |
| `cmd_volume_down.mp3` | Сделала потише | `(smiling, friendly, warm) Сделала потише!` | сделай тише |
| `cmd_volume_mute.mp3` | Выключила звук | `(smiling, friendly, warm) Выключила звук!` | выключи звук |
| `cmd_volume_unmute.mp3` | Вернула звук | `(smiling, friendly, warm) Вернула звук!` | включи звук |
| `cmd_volume_up.mp3` | Сделала погромче | `(smiling, friendly, warm) Сделала погромче!` | сделай громче |

### Блоки для копипаста в Fish (cmd)

```
(smiling, friendly, warm) Сделала потемнее!
(smiling, friendly, warm) Сделала поярче!
(smiling, friendly, warm) Вернула назад!
(smiling, friendly, warm) Закрыла вкладку!
(smiling, friendly, warm) Открыла загрузки!
(smiling, friendly, warm) Открыла инкогнито!
(smiling, friendly, warm) Открыла новую вкладку!
(smiling, friendly, warm) Перешла на следующую!
(smiling, friendly, warm) Открыла браузер!
(smiling, friendly, warm) Вернула прошлую вкладку!
(smiling, friendly, warm) Обновила!
(smiling, friendly, warm) Вернула вкладку!
(smiling, friendly, warm) Отменила выключение!
(smiling, friendly, warm) Открыла буфер!
(smiling, friendly, warm) Закрыла!
(smiling, friendly, warm) Диктуй, я слушаю!
(smiling, friendly, warm) Очистила корзину!
(smiling, friendly, warm) Включила игровой режим!
(smiling, friendly, warm) Выключила жесты!
(smiling, friendly, warm) Включила жесты!
(smiling, friendly, warm) Скопировала!
(smiling, friendly, warm) Вырезала!
(smiling, friendly, warm) Открыла поиск!
(smiling, friendly, warm) Сделала новый документ!
(smiling, friendly, warm) Вставила!
(smiling, friendly, warm) Отправила на печать!
(smiling, friendly, warm) Вернула как было!
(smiling, friendly, warm) Сохранила!
(smiling, friendly, warm) Выделила всё!
(smiling, friendly, warm) Переключила язык!
(smiling, friendly, warm) Отменила!
(smiling, friendly, warm) Заблокировала!
(smiling, friendly, warm) Развернула на весь экран!
(smiling, friendly, warm) Включила следующий!
(smiling, friendly, warm) Поставила на паузу!
(smiling, friendly, warm) Вернула прошлый трек!
(smiling, friendly, warm) Остановила!
(smiling, friendly, warm) Всё свернула!
(smiling, friendly, warm) Свернула!
(smiling, friendly, warm) Открыла про компьютер!
(smiling, friendly, warm) Открыла Авито!
(smiling, friendly, warm) Открыла блютуз!
(smiling, friendly, warm) Открыла калькулятор!
(smiling, friendly, warm) Открыла календарь!
(smiling, friendly, warm) Открыла камеру!
(smiling, friendly, warm) Открыла Чатджипити!
(smiling, friendly, warm) Открыла Клода!
(smiling, friendly, warm) Открыла Курсор!
(smiling, friendly, warm) Открыла Дипсик!
(smiling, friendly, warm) Открыла рабочий стол!
(smiling, friendly, warm) Открыла Дискорд!
(smiling, friendly, warm) Открыла настройки экрана!
(smiling, friendly, warm) Открыла документы!
(smiling, friendly, warm) Открыла загрузки!
(smiling, friendly, warm) Открыла эмодзи!
(smiling, friendly, warm) Открыла Эксель!
(smiling, friendly, warm) Открыла проводник!
(smiling, friendly, warm) Открыла Джемини!
(smiling, friendly, warm) Открыла Гитхаб!
(smiling, friendly, warm) Открыла почту!
(smiling, friendly, warm) Открыла Гугл диск!
(smiling, friendly, warm) Открыла Инстаграм!
(smiling, friendly, warm) Открыла Иви!
(smiling, friendly, warm) Открыла Кинопоиск!
(smiling, friendly, warm) Открыла карты!
(smiling, friendly, warm) Открыла Мит!
(smiling, friendly, warm) Открыла Нетфликс!
(smiling, friendly, warm) Открыла новости!
(smiling, friendly, warm) Включила ночной свет!
(smiling, friendly, warm) Открыла блокнот!
(smiling, friendly, warm) Открыла Ноушен!
(smiling, friendly, warm) Открыла ОБС!
(smiling, friendly, warm) Открыла Озон!
(smiling, friendly, warm) Открыла Пейнт!
(smiling, friendly, warm) Открыла фото!
(smiling, friendly, warm) Открыла Пинтерест!
(smiling, friendly, warm) Открыла презентацию!
(smiling, friendly, warm) Открыла корзину!
(smiling, friendly, warm) Открыла Рутуб!
(smiling, friendly, warm) Открыла скриншоты!
(smiling, friendly, warm) Открыла параметры!
(smiling, friendly, warm) Открыла ножницы!
(smiling, friendly, warm) Открыла звук!
(smiling, friendly, warm) Открыла автозагрузку!
(smiling, friendly, warm) Открыла Стим!
(smiling, friendly, warm) Открыла память!
(smiling, friendly, warm) Открыла диспетчер!
(smiling, friendly, warm) Открыла Тимс!
(smiling, friendly, warm) Открыла Телеграм!
(smiling, friendly, warm) Открыла терминал!
(smiling, friendly, warm) Открыла Тикток!
(smiling, friendly, warm) Открыла переводчик!
(smiling, friendly, warm) Открыла Твич!
(smiling, friendly, warm) Открыла обновления!
(smiling, friendly, warm) Открыла Вконтакте!
(smiling, friendly, warm) Открыла погоду!
(smiling, friendly, warm) Открыла Ватсап!
(smiling, friendly, warm) Открыла вайфай!
(smiling, friendly, warm) Открыла Вайлдберриз!
(smiling, friendly, warm) Открыла Ворд!
(smiling, friendly, warm) Открыла Яндекс!
(smiling, friendly, warm) Открыла Яндекс диск!
(smiling, friendly, warm) Открыла Яндекс карты!
(smiling, friendly, warm) Открыла Яндекс музыку!
(smiling, friendly, warm) Открыла Ютуб!
(smiling, friendly, warm) Открыла Ютуб музыку!
(smiling, friendly, warm) Открыла Зум!
(smiling, friendly, warm) Перезапустила проводник!
(smiling, friendly, warm) Хорошо, напомню!
(smiling, friendly, warm) Убрала напоминание!
(smiling, friendly, warm) Перезагружаю!
(smiling, friendly, warm) Сделала скриншот!
(smiling, friendly, warm) Ищу в Гугле!
(smiling, friendly, warm) Открыла Википедию!
(smiling, friendly, warm) Ищу в Яндексе!
(smiling, friendly, warm) Ищу на Ютубе!
(smiling, friendly, warm) Показала рабочий стол!
(smiling, friendly, warm) Выключаю!
(smiling, friendly, warm) Усыпляю компьютер!
(smiling, friendly, warm) Читаю!
(smiling, friendly, warm) Хорошо, остановила!
(smiling, friendly, warm) Переключила окно!
(smiling, friendly, warm) Поставила таймер!
(smiling, friendly, warm) Открыла переводчик!
(smiling, friendly, warm) Поставила Хром!
(smiling, friendly, warm) Поставила Яндекс браузер!
(smiling, friendly, warm) Сделала потише!
(smiling, friendly, warm) Выключила звук!
(smiling, friendly, warm) Вернула звук!
(smiling, friendly, warm) Сделала погромче!
```

---

## C. Итого

- реакции: **31**
- cmd_*: **132**
- **всего 163** mp3

## D. Не озвучивать
- `not_found` / `error` — тишина (как у Миты)

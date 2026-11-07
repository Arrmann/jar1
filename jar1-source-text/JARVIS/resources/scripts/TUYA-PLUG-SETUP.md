# Умная розетка (Tuya / Smart Life) + JARVIS

Большинство Wi‑Fi розеток с Ozon/Ali — это **Tuya**. Их нужно один раз завести в приложение, потом JARVIS рулит **локально** (без облака на каждое «включи»).

## 1. Физическая настройка

1. Вставь розетку в розетку 220V.
2. Wi‑Fi роутера должен быть **2.4 GHz** (многие не видят 5 GHz).
3. Поставь **Smart Life** или **Tuya Smart** на телефон.
4. В приложении добавь устройство (обычно мигающий индикатор → режим сопряжения).
5. Убедись, что розетка и ПК в **одной домашней сети**.

Если розетка Xiaomi / Sonoff / Matter — напиши, сделаем другой бэкенд. Этот путь — под Tuya.

## 2. Ключи для локального управления

JARVIS нужен не логин Smart Life, а:
- `id` (device id)
- `local_key`
- `ip` в локалке

Самый простой путь:

1. Зарегистрируй бесплатный проект на https://iot.tuya.com (регион EU/US — как удобно).
2. В Cloud → Development создай Cloud Project, привяжи аккаунт Smart Life.
3. В терминале:

```bat
C:\jarvisTOP\resources\tts\runtime\python\python.exe -m tinytuya wizard
```

4. Скопируй id / key / ip и добавь:

```bat
C:\jarvisTOP\resources\scripts\tuya-plug.cmd add --name розетка --id bfXXXX --key XXXX --ip 192.168.1.50
```

Конфиг лежит тут:
`%APPDATA%\com.jarvisn.assistant\tuya-plug.json`

## 3. Голосовые команды

- «включи розетку» / «выключи розетку»
- «выключи розетку через десять секунд / минуту / пять минут / час»
- «включи розетку через минуту / час»
- «отмени таймер розетки»
- «настрой розетку» — подсказка
- «статус розетки»

Проверка вручную:

```bat
tuya-plug.cmd on
tuya-plug.cmd off
tuya-plug.cmd status
tuya-plug.cmd timer 10s
```

После правок команд перезапусти JARVIS через `START_JARVIS.bat`.

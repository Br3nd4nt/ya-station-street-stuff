# Кастомные кнопки для Yandex Station Street (mango)

Рабочий журнал. Цель: кнопки работают на старте без `maind --platformd`
(режим "бункера"), через собственный демон `buttonsd`.

## Статус на 2026-10-26

- [x] SSH/ADB доступ, устройство `192.168.10.185:2222`, root без пароля.
- [x] Собрана карта input-устройств и их key capabilities.
- [x] Написан и собран `buttonsd` (ARM32, musl, static).
- [x] Написан установщик + init-скрипт автозапуска `/etc/init.d/S98buttonsd`.
- [x] `buttonsd` запущен на колонке в пассивном режиме (`grab=0`, maind не трогаем).
- [x] Подтвердить физические кнопки живым нажатием (capture).
- [x] Проверить громкость/mute/батарею/LED вручную.
- [x] Перевести колонку в bunker-режим и проверить автозапуск после reboot.
- [x] Проверить сохранение mute/volume между перезагрузками.
- [ ] Проверить long-press / repeat живым удержанием.
- [ ] Проверить визуально LED-отклик в bunker-режиме.
- [ ] Решить, что должны делать `play_pause` и `bluetooth` (сейчас только лог + хуки).

### Bunker-тест (выполнен)

1. `killswitch.sh on` заменил `launch.json` на пустой список задач и перезагрузил колонку.
2. После reboot:
   - `maind` вообще нет;
   - `quasar_launcher2` жив с пустым `launch.json`;
   - `buttonsd` автоматически стартовал из `/etc/init.d/S98buttonsd` (pid есть);
   - все event0/2/3 открыты;
   - громкость восстановлена из состояния.
3. Mute, нажатый до reboot, корректно восстановился как mute (0%, saved 20%).
4. Возврат в штатный режим: `sh /data/opt/bin/killswitch.sh off` + reboot.

LED: `buttons_led.sh` теперь на время действия снимает триггеры `ledfb-*`
(иначе maind/framebuffer перетирает brightness) и возвращает их после.
В bunker-режиме это должно давать видимую вспышку. Нужна визуальная проверка.

### Защита штатного режима

Добавлен `suspend_with_maind=1`: `buttonsd` каждые 3 секунды смотрит
`/proc/*/cmdline` и, если находит `maind --platformd`, приостанавливает
действия (события не обрабатываются, двойных нажатий нет). Когда maind
исчезает — действия возобновляются. Проверено оба режима:

- normal: maind запущен, в логе `maind --platformd detected: actions suspended`;
- bunker: maind нет, в логе только `listening ...`, действия активны.

### Пульсация Алисы и заряд (найдено)

Пульсация — не `maind` и не sysfs-триггер, а аппаратная i2c-анимация:

```text
/sys/devices/platform/logo-animation/start
/sys/devices/platform/logo-animation/stop
/sys/devices/platform/charge-animation/start
/sys/devices/platform/charge-animation/stop
```

В dmesg: `i2c-animation logo-animation: Starting the animation` →
в bunker без maind она не останавливается. Запись `0` в `stop` даёт
`i2c-animation logo-animation: Animation done`; зарядные диоды гаснут.

Решение:

- `/etc/init.d/S05ledoff` — ранний стоп анимаций. Работает **только если**
  в `launch.json` пустой `"tasks": []` (bunker). Ждёт sysfs драйвера,
  пишет `0` в оба `stop`, ставит всем LED `trigger=none`, `brightness=0`.
- `/etc/init.d/S50ledoff` — такой же fallback позже.
- В normal mode скрипты ничего не делают: `maind` сам ставит
  `ledfb-logo` / `ledfb-charge`, иначе его LEDs ломаются.
- Проверено: normal mode — триггеры `ledfb-logo`/`ledfb-charge`;
  bunker — `none`, brightness 0; анимация гаснет на ~4-й секунде boot.

### Логика кнопок (bunker)

| Кнопка | Действие |
|---|---|
| Алиса short | синяя вспышка + hook `on_activate.sh` |
| Алиса long | красная заливка + hook `on_activate_long.sh` |
| Громкость ± | `amixer` шаг 5%, bar на кольце, repeat при удержании |
| Mute | сохранить уровень → 0%, кольцо красное; повтор — вернуть уровень и bar |
| Питание | заряд на 4 диодах зарядки (1–4 сегмента) на 2 сек + лог |
| Пауза/продолжить | `spotiya --toggle` (Spotify Connect) + зелёная вспышка |
| Bluetooth | `bluetoothctl power on`, pairable, discoverable 120 с + синяя вспышка |
| Долгое питание | только hook `on_power_long.sh` (безопасно, без poweroff по умолчанию) |

Громкость/mute/заряд переживают reboot через `/data/opt/var/lib/buttonsd/`.

### Текущее состояние (2026-10-26 20:36)

- Колонка в **bunker-режиме**: `launch.json` пуст, `maind` не запущен.
- `buttonsd` работает, pid 1074.
- Громкость 20%, mute выключен.
- init-скрипт `/etc/init.d/S98buttonsd` установлен и переживает reboot.
- Возврат: `sh /data/opt/bin/killswitch.sh off` + reboot.

### Что осталось

- Визуально проверить LED в bunker (Алиса → синяя вспышка, питание → заряд).
- Проверить удержание: громкость должна повторяться, Алиса long → красный.
- Решить поведение `play_pause` и `bluetooth`: сейчас только запись в лог,
  дальше — через `cmd_*` или hook `on_*.sh`.
- При желании `grab=1` в bunker, чтобы гарантировать монополию на evdev.

### Подтверждённая карта (живые нажатия, 2026-10-26)

| Кнопка | Узел | code | logical |
|---|---|---:|---|
| Алиса | event3 `adc_keypad` | 582 `KEY_VOICECOMMAND` | `activate` |
| Громкость + | event3 | 115 `KEY_VOLUMEUP` | `volume_up` |
| Громкость − | event3 | 114 `KEY_VOLUMEDOWN` | `volume_down` |
| Пауза/продолжить | event3 | 119 `KEY_PAUSE` | `play_pause` |
| Bluetooth | event3 | 237 `KEY_BLUETOOTH` | `bluetooth` |
| Отключение микрофона | event0 `gpio_keypad` | 113 `KEY_MUTE` (+ `EV_SW` 14) | `mute` |
| Питание | event0 | 116 `KEY_POWER` | `power` |

Нажатия видны и в `/data/cap_buttons.log` (evcap), и в
`/data/opt/var/log/buttonsd.log` (actions).

### Проверено вручную

- `buttons_volume.sh down/up`: 20% → 15% → 10% → 15%.
- `buttons_mute.sh`: сохраняет 15%, ставит 0%.
- `buttons_volume.sh up` при mute: восстанавливает и поднимает до 20%.
- `buttons_battery.sh`: `battery 100%`.
- `buttons_led.sh pulse`: выполняется без ошибок.
- Старый баг `set_volume.sh -5` (`amixer: invalid option -- '5'`) исправлен
  переходом на `amixer set Master 5%-` / `5%+`.

## Железо и input-узлы

| Узел | Имя | Key capabilities (декодировано) |
|---|---|---|
| event0 | `gpio_keypad` | `KEY_MUTE` (113), `KEY_POWER` (116) |
| event1 | `accel` | акселерометр, не кнопки |
| event2 | `input_btrcu` | `KEY_COPY` (133), `KEY_POWER` (116) |
| event3 | `adc_keypad` | `KEY_VOICECOMMAND` (582), `KEY_BLUETOOTH` (237), `KEY_COFFEE` (152), `KEY_VOLUMEDOWN` (114), `KEY_VOLUMEUP` (115), `KEY_PAUSE` (119) |
| event4 | AVRCP BT | не открываем: это медиа-клавиши BT-источника, не кнопки колонки |

`maind --platformd` держит открытыми event0–event3. EVDEV не эксклюзивен,
поэтому `buttonsd` может читать те же узлы параллельно (`grab=0`).
При `grab=1` `buttonsd` делает `EVIOCGRAB` и забирает события у maind —
включать только когда maind выключен.

Подтверждённое соответствие кнопок (живые нажатия):

| Кнопка | code | logical |
|---|---:|---|
| Алиса | 582 `KEY_VOICECOMMAND` | `activate` |
| Громкость + | 115 `KEY_VOLUMEUP` | `volume_up` |
| Громкость − | 114 `KEY_VOLUMEDOWN` | `volume_down` |
| Mute | 113 `KEY_MUTE` | `mute` |
| Кнопка действия / питание | 116 `KEY_POWER` | `power` |
| Play/pause (если есть) | 119 `KEY_PAUSE` | `play_pause` |
| BT-комбинация | 237 `KEY_BLUETOOTH` | `bluetooth` |

В логах maind уже встречались `Button Event: power` и `Button Event: bluetooth`
(`buttons_handler.cpp:373`), это подтверждает логические имена.

## Что не требует maind

- Громкость: `/system/vendor/quasar/set_volume.sh 20` → `amixer set Master 20%`.
  Проверено, микшер живой, `Master` 0–255.
- Mute: своего switch у `Master` нет, поэтому `buttons_mute.sh` сохраняет
  громкость в `buttons_mute.state` и ставит 0%, затем восстанавливает.
- LED: `/sys/class/leds/mango:{red,green,blue}:logo{0,1,2}/brightness`,
  заряд — `mango:red:charge{0..3}`. Триггеры сейчас `ledfb-logo`/`ledfb-charge`
  (их рисует maind через framebuffer). Для bunker-режима используем `ring.sh`
  (он сохраняет и восстанавливает триггеры).
- Батарея: `/sys/devices/virtual/ip2366_cls/ip2366_charger/capacity`.

## Файлы

- `bin/buttonsd.c` — демон: evdev → short/long/repeat → hook/command.
- `bin/evcap.c` — утилита захвата событий для разметки кнопок.
- `scripts/buttons_led.sh`, `buttons_volume.sh`, `buttons_mute.sh`,
  `buttons_battery.sh`, `buttons_playpause.sh`, `buttons_bluetooth.sh` — действия.
- `system_files/buttonsd.conf` — конфиг (устройства, тайминги, overrides).
- `system_files/S98buttonsd` — init-скрипт автозапуска.
- `system_files/S05ledoff`, `S50ledoff` — ранний стоп preboot-анимаций (bunker).
- `scripts/install-buttonsd.sh` / `uninstall-buttonsd.sh` — установка.
- `scripts/st-wait.sh`, `st-ssh.sh` — ожидание колонки, если Wi-Fi отвалился.

## Как работает buttonsd

- Читает event0/2/3 через `poll`, `EV_KEY`, value 1/0.
- Маппинг code → имя, настраивается `map_<code>=<name>`.
- Short press: действие на release (кроме громкости — сразу на press).
- Long press: через `long_ms` (900 мс), действие `<name>_long`.
- Громкость: шаг сразу, затем repeat каждые 180 мс после 500 мс удержания.
- Приоритет действия: hook `on_<name>[_long].sh` → `cmd_<name>` → встроенное.
- Встроенные действия:
  - `volume_up/down` → `buttons_volume.sh up/down` + bar;
  - `mute` → `buttons_mute.sh` + красное кольцо;
  - `activate` → синяя вспышка, `activate_long` → красный fill;
  - `power` → `buttons_battery.sh` (заряд на диодах зарядки);
  - `play_pause` → `buttons_playpause.sh` (`spotiya --toggle`);
  - `bluetooth` → `buttons_bluetooth.sh` (pairing 120 с).
- Хуки запускаются асинхронно (fork+exec), event-loop не блокируется.
- Лог: `/data/opt/var/log/buttonsd.log`.
- PID: `/data/opt/var/run/buttonsd.pid`.

## Установка / управление

```sh
./scripts/install-buttonsd.sh          # залить + поставить автозапуск + старт
./scripts/st-ssh.sh '/etc/init.d/S98buttonsd status'
./scripts/st-ssh.sh '/etc/init.d/S98buttonsd restart'
./scripts/uninstall-buttonsd.sh        # убрать автозапуск
```

Скрипты сами ждут колонку (ping + ssh) до 300 с, поэтому краткие обрывы Wi-Fi
не ломают установку.

## Bunker-режим (ВКЛЮЧЁН)

`scripts/killswitch.sh on` заменяет `launch.json` пустым списком задач и
перезагружает колонку. `buttonsd` стартует из `/etc/init.d/S98buttonsd`
независимо от quasar_launcher2. S05/S50ledoff видят пустой `tasks` и гасят
preboot-анимации. `grab=1` не обязателен: maind нет.

Важно: вместе с `maind --platformd` уйдут Алиса, медиа, telemetry, обновления.
Громкость/mute/LED через `amixer` и sysfs продолжат работать. Воспроизведение
музыки зависит от того, кто ещё владеет ALSA (например, spotify-connect).

## Открытые вопросы

1. Точный code кнопки Алисы и кнопки действия — подтвердить нажатием.
2. Что должна делать кнопка Алисы в кастомном режиме: скрипт, HTTP/MQTT,
   запись звука, свой voice-клиент? Сейчас по умолчанию только LED + лог.
3. Нужен ли `grab=1` по умолчанию в bunker-режиме.
4. Проверить, не перерисовывает ли `ledfb` триггер LED после остановки maind.

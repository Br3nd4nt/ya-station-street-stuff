LAUNCH_JSON="/system/vendor/quasar/launch.json"
BACKUP_JSON="/data/quasar/launch.json.backup"

status() {
    if ps | grep -E 'maind|platformd' | grep -v grep >/dev/null 2>&1; then
        echo "[STATUS] Штатный режим: Quasar активен, Алиса подключена к облаку."
    else
        echo "[STATUS] РЕЖИМ БУНКЕРА: Quasar выключен, колонка изолирована от серверов Яндекса."
    fi
}




enable_bunker() {
    echo "[*] Активация Режима Бункера (Kill Switch)..."
    mount -o remount,rw / || { echo "Ошибка remount rw!"; exit 1; }

    # 1. Бэкапим рабочий launch.json, если бэкапа ещё нет
    mkdir -p /data/quasar
    if [ ! -f "$BACKUP_JSON" ] && [ -f "$LAUNCH_JSON" ]; then
        cp -f "$LAUNCH_JSON" "$BACKUP_JSON"
        echo "[+] Бэкап launch.json сохранён в $BACKUP_JSON"
    fi

    # 2. Подменяем launch.json на пустой список задач
    # (quasar_launcher2 остаётся жить для watchdog, но демоны maind/platformd не стартуют)
    cat << 'EOF' > "$LAUNCH_JSON"
{
  "nodes": [
    {
      "name": "main",
      "root": ".",
      "tasks": []
    }
  ]
}
EOF
    mount -o remount,ro /
    echo "[OK] Режим бункера установлен! Колонка перезагружается в режим изоляции..."
    sync
    reboot
}

disable_bunker() {
    echo "[*] Отключение Режима Бункера и воскрешение Алисы..."
    mount -o remount,rw / || { echo "Ошибка remount rw!"; exit 1; }

    # 1. Восстанавливаем оригинальный launch.json
    if [ -f "$BACKUP_JSON" ]; then
        cp -f "$BACKUP_JSON" "$LAUNCH_JSON"
        echo "[+] Рабочий launch.json восстановлен из бэкапа."
    else
        echo "[!] Предупреждение: Бэкап не найден, используем дефолтный шаблон."
    fi

    mount -o remount,ro /
    echo "[OK] Алиса включена! Колонка перезагружается в штатный режим..."
    sync
    reboot
}

case "$1" in
    on|enable)
        enable_bunker
        ;;
    off|disable)
        disable_bunker
        ;;
    status)
        status
        ;;
    *)
        echo "Использование: sh $0 {on|off|status}"
        exit 1
        ;;
esac
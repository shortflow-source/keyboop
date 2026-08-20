#!/bin/bash
# Локальный цикл: собрать персональную копию → положить в /Applications → перезапустить.
# Отдельные имя, bundle ID и постоянная подпись не смешивают её с официальным Keyboop.
set -e
cd "$(dirname "$0")"

bash build-app.sh

APP="Keyboop Personal.app"
DEST="/Applications/Keyboop Personal.app"
VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null)
echo "▸ Перезапуск и установка в /Applications (v$VER)…"

# Закрыть работающий экземпляр (мягко, потом жёстко).
osascript -e 'tell application "Keyboop Personal" to quit' 2>/dev/null || true
pkill -f "$DEST/Contents/MacOS/Keyboop" 2>/dev/null || true
sleep 0.6

# Заменить в /Applications. Сначала удаляем только точный персональный путь, затем используем ditto:
# так внутри существующего каталога не появится второй вложенный бандл и подпись останется целой.
rm -rf "$DEST"
ditto "$APP" "$DEST"

# Пост-проверка установленного бандла: версия совпадает, нет вложенности, подпись цела.
INST_VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$DEST/Contents/Info.plist" 2>/dev/null)
if [ -e "$DEST/$APP" ]; then
  echo "  ⚠️  ОШИБКА: вложенный бандл — установка битая!"
elif [ "$INST_VER" != "$VER" ]; then
  echo "  ⚠️  ОШИБКА: установлена v$INST_VER, ожидалась v$VER — старая версия не заменилась!"
elif codesign --verify --deep --strict "$DEST" 2>/dev/null; then
  echo "  проверка установки: v$INST_VER, подпись --deep --strict OK (TCC стабилен)"
else
  echo "  ⚠️  ОШИБКА: установленный бандл не проходит codesign --deep --strict (TCC будет слетать)"
fi

# Запустить свежую версию.
open "$DEST"
BID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$DEST/Contents/Info.plist")
echo "✓ Установлено и запущено: $DEST  (v$VER, $BID)"
echo "  Эта персональная сборка только уведомляет об обновлениях и ничего не устанавливает."

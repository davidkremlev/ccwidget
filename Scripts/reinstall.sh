#!/bin/bash
#
# Сборка и переустановка CCWidget.app для разработки.
#
# Последний шаг — killall chronod — обязателен. Без него демон виджетов
# продолжает крутить прежнюю сборку расширения, и правки выглядят
# неприменившимися. Подробнее в SPEC.md, раздел 5.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-Release}"
DERIVED="$ROOT/.build/dd"
APP="/Applications/CCWidget.app"

echo "==> Сборка ($CONFIGURATION)"
xcodebuild \
    -project "$ROOT/CCWidget.xcodeproj" \
    -scheme CCWidget \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED" \
    build \
    | grep -E "error:|warning:|BUILD" || true

BUILT="$DERIVED/Build/Products/$CONFIGURATION/CCWidget.app"
if [ ! -d "$BUILT" ]; then
    echo "!! Сборка не дала бандла: $BUILT" >&2
    exit 1
fi

echo "==> Остановка запущенных копий"
pkill -f "$APP" 2>/dev/null || true
pkill -f CCWidgetExtension 2>/dev/null || true
sleep 2

echo "==> Установка в $APP"
rm -rf "$APP"
cp -R "$BUILT" "$APP"
codesign -v --deep --strict "$APP"
sleep 1

echo "==> Запуск (регистрирует расширение в системе)"
open "$APP"
sleep 3

# Демон виджетов держит расширение загруженным и переживает подмену бандла.
# Если его не перезапустить, он отрисует старый код поверх новых файлов —
# и это выглядит так, будто правки не применились.
echo "==> Перезапуск демона виджетов"
killall chronod 2>/dev/null || true

echo "==> Готово. Логи:"
echo "    log stream --predicate 'subsystem == \"dev.illvminat.ccwidget\"' --level info"

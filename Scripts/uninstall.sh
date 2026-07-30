#!/bin/bash
#
# Снимает установку ccwidget.
#
# Дублирует кнопку «Remove…» в приложении и существует как страховка: если
# приложение не запускается или уже удалено, кнопки нет, а следы в конфиге
# остались. Инструмент, который правит чужой файл и прописывает
# автозапускаемую команду, обязан уметь себя убрать без себя самого.
#
# Ключ statusLine удаляется точечно, а не откатом из копии: между установкой
# и удалением можно было менять другие ключи, и откат файла целиком отобрал
# бы эти правки.
#
#   ./Scripts/uninstall.sh              # снять установку, историю оставить
#   ./Scripts/uninstall.sh --purge      # заодно удалить историю и приложение
#   ./Scripts/uninstall.sh --dry-run    # только показать, что будет сделано
#
set -euo pipefail

WIDGET_ID="dev.illvminat.ccwidget.widget"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
EXPORTER="$CLAUDE_DIR/ccwidget-export.py"
INTEGRITY="$CLAUDE_DIR/.ccwidget-export.sha256"
EXCHANGE="$HOME/Library/Containers/$WIDGET_ID/Data/Library/Application Support/ccwidget"
CONTAINER="$HOME/Library/Containers/$WIDGET_ID"
APP="/Applications/CCWidget.app"

PURGE=0
DRY=0
for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        --dry-run) DRY=1 ;;
        *) echo "неизвестный аргумент: $arg" >&2; exit 2 ;;
    esac
done

run() {
    if [ "$DRY" -eq 1 ]; then echo "    [сухой прогон] $*"; else "$@"; fi
}

echo "==> Что будет сделано"

# --- statusLine ---
if [ -f "$SETTINGS" ] && grep -q "ccwidget-export.py" "$SETTINGS" 2>/dev/null; then
    echo "    из settings.json удаляется ключ statusLine (остальные не трогаются)"
    REMOVE_KEY=1
else
    echo "    statusLine на нас не указывает — settings.json не трогаем"
    REMOVE_KEY=0
fi

[ -f "$EXPORTER" ] && echo "    удаляется $EXPORTER" || echo "    экспортёра нет"

HISTORY_LINES=0
[ -f "$EXCHANGE/history.jsonl" ] && HISTORY_LINES=$(wc -l < "$EXCHANGE/history.jsonl" | tr -d ' ')
if [ "$PURGE" -eq 1 ]; then
    echo "    удаляется история ($HISTORY_LINES точек) — прогноз начнётся заново"
    echo "    удаляется $APP"
else
    echo "    история сохраняется ($HISTORY_LINES точек); удалить — запустите с --purge"
    echo "    $APP остаётся; удалить — вручную или с --purge"
fi
echo

if [ "$DRY" -eq 0 ]; then
    printf "Продолжить? [y/N] "
    read -r answer
    case "$answer" in y|Y|yes|Yes) ;; *) echo "отменено"; exit 0 ;; esac
fi

# --- удаление ключа с сохранением форматирования ---
if [ "$REMOVE_KEY" -eq 1 ]; then
    STAMP=$(date +%Y%m%d-%H%M%S)
    BACKUP="$CLAUDE_DIR/settings.json.bak-$STAMP"
    echo "==> Копия настроек: $(basename "$BACKUP")"
    if [ "$DRY" -eq 0 ]; then
        cp "$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$SETTINGS")" "$BACKUP"
        chmod 600 "$BACKUP"
    fi

    echo "==> Удаление ключа statusLine"
    if [ "$DRY" -eq 0 ]; then
        python3 - "$SETTINGS" <<'PY'
import json, os, sys

path = os.path.realpath(sys.argv[1])
with open(path) as f:
    text = f.read()

data = json.loads(text)
if "statusLine" not in data:
    sys.exit(0)
del data["statusLine"]

# Пытаемся вырезать только этот ключ, чтобы не потерять отступы соседей.
# Не вышло — пересобираем и говорим об этом.
import re
pattern = re.compile(r'\n[ \t]*"statusLine"\s*:\s*\{[^{}]*\}\s*,?', re.S)
edited, count = pattern.subn("", text, count=1)
if count:
    edited = re.sub(r',(\s*\})', r'\1', edited)
try:
    ok = count and json.loads(edited) == data
except ValueError:
    ok = False

if ok:
    with open(path, "w") as f:
        f.write(edited)
    print("    ключ вырезан, форматирование остального сохранено")
else:
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("    точечно не вышло: файл пересобран, порядок ключей и отступы изменились")
    print("    исходник — в копии рядом")
PY
    fi
fi

echo "==> Удаление экспортёра"
run rm -f "$EXPORTER" "$INTEGRITY"

if [ "$PURGE" -eq 1 ]; then
    echo "==> Удаление истории и контейнера"
    run rm -rf "$CONTAINER"
    echo "==> Удаление приложения"
    run rm -rf "$APP"
    echo "==> Перезапуск демона виджетов"
    [ "$DRY" -eq 0 ] && killall chronod 2>/dev/null || true
fi

echo
echo "==> Готово"
if [ "$PURGE" -eq 0 ]; then
    echo "    Осталось убрать вручную, если нужно:"
    echo "      $APP"
    echo "      $CONTAINER"
    echo "    И снять виджет с рабочего стола."
fi

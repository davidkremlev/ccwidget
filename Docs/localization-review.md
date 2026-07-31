# Localization review

The interface ships in six languages. **English and Russian are first-language
work. German, Spanish, Japanese and Simplified Chinese are not** — they are one
developer's best effort, and they want a native speaker's eye before anyone
relies on them.

This file is generated from the string catalogs by
`./Scripts/localization-review.py`. Edit the catalogs, not this.

## What is being asked

Not a translation project. A read-through, looking for the two things a
dictionary cannot catch:

1. **Sentences nobody says.** A translation can be word-for-word correct and
   still read like a machine wrote it. This has already happened here: the row
   captions used to be `Woche genutzt` in German and `Semana usada` in Spanish,
   both of which mean "a week that was used" rather than "how much of the week
   you have used". They were rewritten after reading them aloud.
2. **Wrong register or wrong term.** This is a small utility that sits on a
   desktop. It should sound like a tool, not like a legal notice or a chat
   message.

## How to send corrections

Open an issue with the key and what it should say. One line is plenty:

```
"Week used" (de) → "Diese Woche verbraucht" reads better as "…"
```

No pull request is needed and no Swift. If you would rather edit directly, the
strings are plain JSON in `App/Resources/Localizable.xcstrings` and
`Widget/Resources/Localizable.xcstrings`, in Apple's String Catalog format.

## Context that changes the wording

- **The three gauge rows all measure consumption**, and all three grow towards
  worse. Whatever they say, more must sound worse — not "70 % remaining" in one
  row and "30 % used" in another.
- **The context window is filled, not spent.** It is not a subscription quota
  and hitting 100 % costs nothing; it means the model starts losing the
  beginning of the conversation. Russian uses a different verb for that row for
  exactly this reason.
- **Space is tight.** A widget tile is 158 or 338 points wide. The medium size
  fits a caption of roughly 22 characters beside a bar and a number; longer
  captions shrink and then truncate. Shorter is better when the choice is
  between shorter and more precise.
- **"Status line"** is the Claude Code feature that feeds this widget — the
  line the CLI redraws under the prompt. It is a proper feature name.
- **"Snapshot", "exporter", "exchange directory", "watcher"** are this
  project's own terms for its parts, defined in `SPEC.md`. Consistency between
  them matters more than elegance in any one.

---

## The strings

`%@` and `%lld` are substituted at runtime — keep them, and keep their order
where the grammar allows. Plural forms are shown as `one:` / `other:` and so
on; a language that needs more categories than are listed is itself a finding.


### In the widget

Seen on the desktop, in tiles 158 to 338 points wide.


**`%@ %%/h`** — Usage rate: a number followed by percent per hour

| | |
|---|---|
| German | %@ %%/Std. |
| Spanish | %@ %%/h |
| Japanese | %@ %%/時 |
| Simplified Chinese | %@ %%/小时 |


**`5-hour used`**

| | |
|---|---|
| German | In 5 Std. verbraucht |
| Spanish | Consumo en 5 h |
| Japanese | 5時間の使用率 |
| Simplified Chinese | 5小时已用 |


**`Cache`**

| | |
|---|---|
| German | Cache |
| Spanish | Caché |
| Japanese | キャッシュ |
| Simplified Chinese | 缓存 |


**`Claude Code %@`**

| | |
|---|---|
| German | Claude Code %@ |
| Spanish | Claude Code %@ |
| Japanese | Claude Code %@ |
| Simplified Chinese | Claude Code %@ |


**`Context used`**

| | |
|---|---|
| German | Kontext belegt |
| Spanish | Contexto ocupado |
| Japanese | コンテキスト使用率 |
| Simplified Chinese | 上下文已用 |


**`Cost`**

| | |
|---|---|
| German | Kosten |
| Spanish | Coste |
| Japanese | コスト |
| Simplified Chinese | 费用 |


**`Data is stale`**

| | |
|---|---|
| German | Daten sind veraltet |
| Spanish | Los datos están obsoletos |
| Japanese | データが古くなっています |
| Simplified Chinese | 数据已过时 |


**`Estimate`**

| | |
|---|---|
| German | Schätzung |
| Spanish | Estimación |
| Japanese | 推定 |
| Simplified Chinese | 估算 |


**`Lasts until reset`**

| | |
|---|---|
| German | Reicht bis zum Reset |
| Spanish | Alcanza hasta el reinicio |
| Japanese | リセットまで持ちます |
| Simplified Chinese | 可撑到重置 |


**`Launch Claude Code`**

| | |
|---|---|
| German | Claude Code starten |
| Spanish | Inicia Claude Code |
| Japanese | Claude Code を起動 |
| Simplified Chinese | 启动 Claude Code |


**`Launch Claude Code in the terminal and send a message.`**

| | |
|---|---|
| German | Starten Sie Claude Code im Terminal und senden Sie eine Nachricht. |
| Spanish | Inicia Claude Code en el terminal y envía un mensaje. |
| Japanese | ターミナルで Claude Code を起動してメッセージを送ってください。 |
| Simplified Chinese | 在终端中启动 Claude Code 并发送一条消息。 |


**`Launch Claude Code in the terminal to refresh.`**

| | |
|---|---|
| German | Starten Sie Claude Code im Terminal, um zu aktualisieren. |
| Spanish | Inicia Claude Code en el terminal para actualizar. |
| Japanese | 更新するにはターミナルで Claude Code を起動してください。 |
| Simplified Chinese | 在终端中启动 Claude Code 以刷新。 |


**`no data`**

| | |
|---|---|
| German | keine Daten |
| Spanish | sin datos |
| Japanese | データなし |
| Simplified Chinese | 无数据 |


**`No data yet`**

| | |
|---|---|
| German | Noch keine Daten |
| Spanish | Aún no hay datos |
| Japanese | まだデータがありません |
| Simplified Chinese | 暂无数据 |


**`Not enough data yet`**

| | |
|---|---|
| German | Noch zu wenig Daten |
| Spanish | Aún no hay datos suficientes |
| Japanese | データがまだ足りません |
| Simplified Chinese | 数据尚不足 |


**`outdated · %@`**

| | |
|---|---|
| German | veraltet · %@ |
| Spanish | obsoleto · %@ |
| Japanese | 古い · %@ |
| Simplified Chinese | 已过时 · %@ |


**`Rate only — too little history for a date`**

| | |
|---|---|
| German | Nur Tempo — zu wenig Verlauf für ein Datum |
| Spanish | Solo ritmo: historial insuficiente para una fecha |
| Japanese | ペースのみ — 日付を出すには履歴が不足 |
| Simplified Chinese | 仅速率 — 历史不足以给出日期 |


**`resets %@ · %@`**

| | |
|---|---|
| German | Reset %@ · %@ |
| Spanish | reinicia %@ · %@ |
| Japanese | %@ にリセット · %@ |
| Simplified Chinese | %@ 重置 · %@ |


**`Runs out ~%@`**

| | |
|---|---|
| German | Aufgebraucht ~%@ |
| Spanish | Se agota ~%@ |
| Japanese | ~%@ に尽きます |
| Simplified Chinese | ~%@ 用尽 |


**`Subscription limits, context window and cost at a glance.`**

| | |
|---|---|
| German | Abo-Limits, Kontextfenster und Kosten auf einen Blick. |
| Spanish | Límites de suscripción, ventana de contexto y coste de un vistazo. |
| Japanese | サブスクリプションの上限、コンテキストウィンドウ、コストをひと目で。 |
| Simplified Chinese | 订阅限额、上下文窗口与费用一目了然。 |


**`This session`**

| | |
|---|---|
| German | Diese Sitzung |
| Spanish | Esta sesión |
| Japanese | このセッション |
| Simplified Chinese | 本次会话 |


**`this session:`**

| | |
|---|---|
| German | diese Sitzung: |
| Spanish | esta sesión: |
| Japanese | このセッション: |
| Simplified Chinese | 本次会话： |


**`Tokens`**

| | |
|---|---|
| German | Tokens |
| Spanish | Tokens |
| Japanese | トークン |
| Simplified Chinese | 令牌 |


**`Usage is flat`**

| | |
|---|---|
| German | Verbrauch stagniert |
| Spanish | Consumo estancado |
| Japanese | 使用量は横ばい |
| Simplified Chinese | 用量持平 |


**`Usage Widget for Claude Code`**

| | |
|---|---|
| German | Usage Widget for Claude Code |
| Spanish | Usage Widget for Claude Code |
| Japanese | Usage Widget for Claude Code |
| Simplified Chinese | Usage Widget for Claude Code |


**`used · resets %@`**

| | |
|---|---|
| German | verbraucht · Reset %@ |
| Spanish | consumido · reinicia %@ |
| Japanese | 使用済み · %@ にリセット |
| Simplified Chinese | 已用 · %@ 重置 |


**`waiting for limits`**

| | |
|---|---|
| German | warte auf Limits |
| Spanish | esperando límites |
| Japanese | 制限を待っています |
| Simplified Chinese | 等待限额 |


**`Week used`**

| | |
|---|---|
| German | Diese Woche verbraucht |
| Spanish | Consumo semanal |
| Japanese | 週の使用率 |
| Simplified Chinese | 本周已用 |


**`· cache %@`**

| | |
|---|---|
| German | · Cache %@ |
| Spanish | · caché %@ |
| Japanese | · キャッシュ %@ |
| Simplified Chinese | · 缓存 %@ |

### In the app window

Seen after clicking the widget, and during setup.


**`%lld field(s) dropped while parsing`**

| | |
|---|---|
| German | _one_: %lld Feld beim Parsen verworfen  ·  _other_: %lld Felder beim Parsen verworfen |
| Spanish | _one_: %lld campo descartado al analizar  ·  _other_: %lld campos descartados al analizar |
| Japanese | _other_: 解析時に %lld 個のフィールドを破棄しました |
| Simplified Chinese | _other_: 解析时丢弃了 %lld 个字段 |


**`%lld history points exist; deleting them resets the forecast.`**

| | |
|---|---|
| German | _one_: Es gibt %lld Verlaufspunkt; ihn zu löschen setzt die Schätzung zurück.  ·  _other_: Es gibt %lld Verlaufspunkte; sie zu löschen setzt die Schätzung zurück. |
| Spanish | _one_: Hay %lld punto de historial; borrarlo reinicia la estimación.  ·  _other_: Hay %lld puntos de historial; borrarlos reinicia la estimación. |
| Japanese | _other_: 履歴が %lld 点あります。削除すると推定は最初からになります。 |
| Simplified Chinese | _other_: 已有 %lld 个历史点；删除后估算将重新开始。 |


**`5-hour used`**

| | |
|---|---|
| German | In 5 Std. verbraucht |
| Spanish | Consumo en 5 h |
| Japanese | 5時間の使用率 |
| Simplified Chinese | 5小时已用 |


**`A copy is saved as %@ next to it first.`**

| | |
|---|---|
| German | Zuvor wird daneben eine Kopie als %@ abgelegt. |
| Spanish | Antes se guarda una copia como %@ al lado. |
| Japanese | その前に %@ という名前でコピーを隣に保存します。 |
| Simplified Chinese | 在此之前会在旁边保存一份名为 %@ 的副本。 |


**`Add the widget to your desktop first, then run setup again.`**

| | |
|---|---|
| German | Fügen Sie das Widget zuerst zum Schreibtisch hinzu und starten Sie die Einrichtung erneut. |
| Spanish | Primero añade el widget al escritorio y vuelve a ejecutar la configuración. |
| Japanese | 先にウィジェットをデスクトップに追加してから、もう一度セットアップしてください。 |
| Simplified Chinese | 请先把小组件添加到桌面，然后重新运行设置。 |


**`Add the widget to your desktop first.`**

| | |
|---|---|
| German | Fügen Sie das Widget zuerst zum Schreibtisch hinzu. |
| Spanish | Primero añade el widget al escritorio. |
| Japanese | 先にウィジェットをデスクトップに追加してください。 |
| Simplified Chinese | 请先把小组件添加到桌面。 |


**`Add the widget to your desktop first. Right-click the desktop, choose Edit Widgets, then come back.`**

| | |
|---|---|
| German | Fügen Sie das Widget zuerst zum Schreibtisch hinzu: Rechtsklick, „Widgets bearbeiten“, dann zurückkommen. |
| Spanish | Primero añade el widget al escritorio: clic derecho, Editar widgets, y vuelve aquí. |
| Japanese | 先にウィジェットをデスクトップに追加してください。デスクトップを右クリックし「ウィジェットを編集」を選んでから戻ってください。 |
| Simplified Chinese | 请先把小组件添加到桌面：右键点击桌面，选择“编辑小组件”，然后返回。 |


**`Add this to ~/.claude/settings.json:`**

| | |
|---|---|
| German | Fügen Sie dies in ~/.claude/settings.json ein: |
| Spanish | Añade esto a ~/.claude/settings.json: |
| Japanese | これを ~/.claude/settings.json に追加: |
| Simplified Chinese | 把这段加入 ~/.claude/settings.json： |


**`Another status line is already configured.`**

| | |
|---|---|
| German | Es ist bereits eine andere Statuszeile konfiguriert. |
| Spanish | Ya hay otra línea de estado configurada. |
| Japanese | 別のステータスラインが既に設定されています。 |
| Simplified Chinese | 已配置了另一个状态行。 |


**`Cancel`**

| | |
|---|---|
| German | Abbrechen |
| Spanish | Cancelar |
| Japanese | キャンセル |
| Simplified Chinese | 取消 |


**`Check again`**

| | |
|---|---|
| German | Erneut prüfen |
| Spanish | Comprobar de nuevo |
| Japanese | もう一度確認 |
| Simplified Chinese | 重新检查 |


**`Check needed`**

| | |
|---|---|
| German | Prüfung nötig |
| Spanish | Requiere revisión |
| Japanese | 確認が必要 |
| Simplified Chinese | 需要检查 |


**`Claude Code`**

| | |
|---|---|
| German | Claude Code |
| Spanish | Claude Code |
| Japanese | Claude Code |
| Simplified Chinese | Claude Code |


**`Claude Code detected.`**

| | |
|---|---|
| German | Claude Code gefunden. |
| Spanish | Claude Code detectado. |
| Japanese | Claude Code を検出しました。 |
| Simplified Chinese | 已检测到 Claude Code。 |


**`Claude Code was not found.`**

| | |
|---|---|
| German | Claude Code wurde nicht gefunden. |
| Spanish | No se encontró Claude Code. |
| Japanese | Claude Code が見つかりません。 |
| Simplified Chinese | 未找到 Claude Code。 |


**`collapsed`** — Whether the Details section of the window is open

| | |
|---|---|
| German | ausgeblendet |
| Spanish | plegado |
| Japanese | 折りたたみ中 |
| Simplified Chinese | 已折叠 |


**`Context used`**

| | |
|---|---|
| German | Kontext belegt |
| Spanish | Contexto ocupado |
| Japanese | コンテキスト使用率 |
| Simplified Chinese | 上下文已用 |


**`Continue`**

| | |
|---|---|
| German | Weiter |
| Spanish | Continuar |
| Japanese | 次へ |
| Simplified Chinese | 继续 |


**`Copy`**

| | |
|---|---|
| German | Kopieren |
| Spanish | Copiar |
| Japanese | コピー |
| Simplified Chinese | 复制 |


**`Copy the template to ~/.claude/ccwidget-export.py`**

| | |
|---|---|
| German | Kopieren Sie die Vorlage nach ~/.claude/ccwidget-export.py |
| Spanish | Copia la plantilla a ~/.claude/ccwidget-export.py |
| Japanese | テンプレートを ~/.claude/ccwidget-export.py にコピー |
| Simplified Chinese | 将模板复制到 ~/.claude/ccwidget-export.py |


**`Could not write %@: %@`**

| | |
|---|---|
| German | %@ konnte nicht geschrieben werden: %@ |
| Spanish | No se pudo escribir %@: %@ |
| Japanese | %@ を書き込めませんでした: %@ |
| Simplified Chinese | 无法写入 %@：%@ |


**`Details`**

| | |
|---|---|
| German | Details |
| Spanish | Detalles |
| Japanese | 詳細 |
| Simplified Chinese | 详细信息 |


**`Done`**

| | |
|---|---|
| German | Fertig |
| Spanish | Listo |
| Japanese | 完了 |
| Simplified Chinese | 完成 |


**`Exchange directory`**

| | |
|---|---|
| German | Austauschverzeichnis |
| Spanish | Directorio de intercambio |
| Japanese | 交換ディレクトリ |
| Simplified Chinese | 交换目录 |


**`expanded`** — Whether the Details section of the window is open

| | |
|---|---|
| German | eingeblendet |
| Spanish | desplegado |
| Japanese | 展開中 |
| Simplified Chinese | 已展开 |


**`Exporter`**

| | |
|---|---|
| German | Exporter |
| Spanish | Exportador |
| Japanese | エクスポーター |
| Simplified Chinese | 导出器 |


**`Exporter will run under %@`**

| | |
|---|---|
| German | Exporter läuft unter %@ |
| Spanish | El exportador se ejecutará con %@ |
| Japanese | エクスポーターは %@ で実行されます |
| Simplified Chinese | 导出器将通过 %@ 运行 |


**`If the widget is not on your desktop yet, right-click the desktop and choose Edit Widgets.`**

| | |
|---|---|
| German | Falls das Widget noch nicht auf dem Schreibtisch ist: Rechtsklick auf den Schreibtisch, „Widgets bearbeiten“. |
| Spanish | Si el widget aún no está en el escritorio, haz clic derecho y elige Editar widgets. |
| Japanese | ウィジェットがまだデスクトップにない場合は、デスクトップを右クリックして「ウィジェットを編集」を選んでください。 |
| Simplified Chinese | 如果小组件还不在桌面上，请右键点击桌面并选择“编辑小组件”。 |


**`Install Claude Code`**

| | |
|---|---|
| German | Claude Code installieren |
| Spanish | Instalar Claude Code |
| Japanese | Claude Code をインストール |
| Simplified Chinese | 安装 Claude Code |


**`installed before checking existed`**

| | |
|---|---|
| German | installiert, bevor es die Prüfung gab |
| Spanish | instalado antes de que existiera la comprobación |
| Japanese | 検証が追加される前に導入 |
| Simplified Chinese | 在校验功能出现前安装 |


**`Launch Claude Code and send any message.`**

| | |
|---|---|
| German | Starten Sie Claude Code und senden Sie eine beliebige Nachricht. |
| Spanish | Inicia Claude Code y envía cualquier mensaje. |
| Japanese | Claude Code を起動して、何かメッセージを送ってください。 |
| Simplified Chinese | 启动 Claude Code 并发送任意消息。 |


**`Live data is coming in.`**

| | |
|---|---|
| German | Live-Daten kommen an. |
| Spanish | Están llegando datos en vivo. |
| Japanese | ライブデータが届いています。 |
| Simplified Chinese | 实时数据已到达。 |


**`Manual setup`**

| | |
|---|---|
| German | Manuelle Einrichtung |
| Spanish | Configuración manual |
| Japanese | 手動セットアップ |
| Simplified Chinese | 手动设置 |


**`matches the installed copy`**

| | |
|---|---|
| German | stimmt mit der installierten Kopie überein |
| Spanish | coincide con la copia instalada |
| Japanese | インストール時のものと一致 |
| Simplified Chinese | 与已安装副本一致 |


**`modified since installation`**

| | |
|---|---|
| German | seit der Installation verändert |
| Spanish | modificado desde la instalación |
| Japanese | インストール後に変更あり |
| Simplified Chinese | 安装后已被修改 |


**`no data`**

| | |
|---|---|
| German | keine Daten |
| Spanish | sin datos |
| Japanese | データなし |
| Simplified Chinese | 无数据 |


**`No working python3 was found. Install the Xcode Command Line Tools with: xcode-select --install`**

| | |
|---|---|
| German | Kein funktionierendes python3 gefunden. Installieren Sie die Xcode Command Line Tools mit: xcode-select --install |
| Spanish | No se encontró un python3 funcional. Instala las Xcode Command Line Tools con: xcode-select --install |
| Japanese | 動作する python3 が見つかりません。xcode-select --install で Xcode Command Line Tools を入れてください。 |
| Simplified Chinese | 未找到可用的 python3。请执行 xcode-select --install 安装 Xcode 命令行工具。 |


**`not installed`**

| | |
|---|---|
| German | nicht installiert |
| Spanish | no instalado |
| Japanese | 未インストール |
| Simplified Chinese | 未安装 |


**`Refresh`**

| | |
|---|---|
| German | Aktualisieren |
| Spanish | Actualizar |
| Japanese | 更新 |
| Simplified Chinese | 刷新 |


**`Reinstall the exporter`**

| | |
|---|---|
| German | Exporter neu installieren |
| Spanish | Reinstalar el exportador |
| Japanese | エクスポーターを入れ直す |
| Simplified Chinese | 重新安装导出器 |


**`Reload widget`**

| | |
|---|---|
| German | Widget neu laden |
| Spanish | Recargar widget |
| Japanese | ウィジェットを再読み込み |
| Simplified Chinese | 重新加载小组件 |


**`Remove and delete history`**

| | |
|---|---|
| German | Entfernen und Verlauf löschen |
| Spanish | Eliminar y borrar el historial |
| Japanese | 削除して履歴も消す |
| Simplified Chinese | 移除并删除历史 |


**`Remove ccwidget?`**

| | |
|---|---|
| German | ccwidget entfernen? |
| Spanish | ¿Eliminar ccwidget? |
| Japanese | ccwidget を削除しますか？ |
| Simplified Chinese | 移除 ccwidget？ |


**`Remove, keep history`**

| | |
|---|---|
| German | Entfernen, Verlauf behalten |
| Spanish | Eliminar y conservar el historial |
| Japanese | 削除して履歴は残す |
| Simplified Chinese | 移除，保留历史 |


**`Removed.`**

| | |
|---|---|
| German | Entfernt. |
| Spanish | Eliminado. |
| Japanese | 削除しました。 |
| Simplified Chinese | 已移除。 |


**`Remove…`**

| | |
|---|---|
| German | Entfernen… |
| Spanish | Eliminar… |
| Japanese | 削除… |
| Simplified Chinese | 移除… |


**`Replace its first line with:`**

| | |
|---|---|
| German | Ersetzen Sie die erste Zeile durch: |
| Spanish | Sustituye su primera línea por: |
| Japanese | 先頭行を次に置き換え: |
| Simplified Chinese | 把第一行替换为： |


**`Replace the GROUP_DIR line with exactly:`**

| | |
|---|---|
| German | Ersetzen Sie die GROUP_DIR-Zeile genau durch: |
| Spanish | Sustituye la línea GROUP_DIR exactamente por: |
| Japanese | GROUP_DIR の行をそのまま次に置き換え: |
| Simplified Chinese | 把 GROUP_DIR 行原样替换为： |


**`running · %lld reloads · last %@`**

| | |
|---|---|
| German | _one_: läuft · %lld Neuladung · zuletzt %@  ·  _other_: läuft · %lld Neuladungen · zuletzt %@ |
| Spanish | _one_: en marcha · %lld recarga · última %@  ·  _other_: en marcha · %lld recargas · última %@ |
| Japanese | _other_: 動作中 · 再読み込み %lld 回 · 最後 %@ |
| Simplified Chinese | _other_: 运行中 · 重新加载 %lld 次 · 最近 %@ |


**`running · no reloads yet`**

| | |
|---|---|
| German | läuft · noch keine Neuladungen |
| Spanish | en marcha · sin recargas aún |
| Japanese | 動作中 · 再読み込みはまだ |
| Simplified Chinese | 运行中 · 尚无重新加载 |


**`Set up automatically`**

| | |
|---|---|
| German | Automatisch einrichten |
| Spanish | Configurar automáticamente |
| Japanese | 自動で設定 |
| Simplified Chinese | 自动设置 |


**`Set up…`**

| | |
|---|---|
| German | Einrichten… |
| Spanish | Configurar… |
| Japanese | 設定… |
| Simplified Chinese | 设置… |


**`Settings backed up as %@`**

| | |
|---|---|
| German | Einstellungen gesichert als %@ |
| Spanish | Ajustes respaldados como %@ |
| Japanese | 設定を %@ としてバックアップしました |
| Simplified Chinese | 设置已备份为 %@ |


**`Settings backed up as %@.`**

| | |
|---|---|
| German | Einstellungen gesichert als %@. |
| Spanish | Ajustes respaldados como %@. |
| Japanese | 設定を %@ としてバックアップしました。 |
| Simplified Chinese | 设置已备份为 %@。 |


**`settings.json had to be rewritten, so key order and indentation changed. The backup has the original.`**

| | |
|---|---|
| German | settings.json musste neu geschrieben werden, Reihenfolge und Einrückung haben sich geändert. Das Original liegt in der Sicherung. |
| Spanish | Hubo que reescribir settings.json, así que el orden y la sangría cambiaron. El original está en la copia. |
| Japanese | settings.json を書き直したため、キーの順序とインデントが変わりました。元はバックアップにあります。 |
| Simplified Chinese | settings.json 不得不重建，键顺序和缩进已改变。原文件在备份中。 |


**`settings.json is a symlink whose target cannot be written. Setup would replace the link with a regular file.`**

| | |
|---|---|
| German | settings.json ist ein Symlink, dessen Ziel nicht beschreibbar ist. Die Einrichtung würde den Link durch eine normale Datei ersetzen. |
| Spanish | settings.json es un enlace simbólico cuyo destino no se puede escribir. La configuración lo reemplazaría por un archivo normal. |
| Japanese | settings.json はシンボリックリンクですが、リンク先に書き込めません。セットアップはリンクを通常のファイルで置き換えてしまいます。 |
| Simplified Chinese | settings.json 是符号链接，但目标不可写。设置会用普通文件替换该链接。 |


**`settings.json is a symlink. Setup writes through it, so the link stays intact.`**

| | |
|---|---|
| German | settings.json ist ein Symlink. Die Einrichtung schreibt hindurch, der Link bleibt erhalten. |
| Spanish | settings.json es un enlace simbólico. La configuración escribe a través de él y el enlace se conserva. |
| Japanese | settings.json はシンボリックリンクです。リンク先に書き込むので、リンクは残ります。 |
| Simplified Chinese | settings.json 是符号链接。设置将写入其目标，链接保持不变。 |


**`settings.json is not writable.`**

| | |
|---|---|
| German | settings.json ist nicht beschreibbar. |
| Spanish | settings.json no se puede escribir. |
| Japanese | settings.json に書き込めません。 |
| Simplified Chinese | settings.json 不可写。 |


**`Setup needed`**

| | |
|---|---|
| German | Einrichtung nötig |
| Spanish | Falta configurar |
| Japanese | 設定が必要 |
| Simplified Chinese | 需要设置 |


**`Setup will replace it. The backup lets you put it back.`**

| | |
|---|---|
| German | Die Einrichtung ersetzt sie. Mit der Sicherung können Sie sie zurückholen. |
| Spanish | La configuración la reemplazará. La copia de seguridad permite restaurarla. |
| Japanese | セットアップはそれを置き換えます。バックアップから戻せます。 |
| Simplified Chinese | 设置将替换它。备份可用于还原。 |


**`Setup writes the exporter to ~/.claude/ and adds one key to settings.json. Only that key changes — your formatting and key order are kept.`**

| | |
|---|---|
| German | Die Einrichtung schreibt den Exporter nach ~/.claude/ und fügt settings.json einen Schlüssel hinzu. Nur dieser ändert sich, Formatierung und Reihenfolge bleiben. |
| Spanish | La configuración escribe el exportador en ~/.claude/ y añade una clave a settings.json. Solo cambia esa clave: tu formato y el orden se conservan. |
| Japanese | セットアップは ~/.claude/ にエクスポーターを書き、settings.json にキーを一つ加えます。変わるのはそのキーだけで、書式と順序は保たれます。 |
| Simplified Chinese | 设置会把导出器写入 ~/.claude/，并向 settings.json 添加一个键。只有该键会变，你的格式与键顺序保持不变。 |


**`Show manual instructions`**

| | |
|---|---|
| German | Manuelle Anleitung zeigen |
| Spanish | Ver instrucciones manuales |
| Japanese | 手動の手順を表示 |
| Simplified Chinese | 显示手动步骤 |


**`Snapshot`**

| | |
|---|---|
| German | Snapshot |
| Spanish | Instantánea |
| Japanese | スナップショット |
| Simplified Chinese | 快照 |


**`stopped`**

| | |
|---|---|
| German | gestoppt |
| Spanish | detenido |
| Japanese | 停止中 |
| Simplified Chinese | 已停止 |


**`Subscription limits on your desktop.`**

| | |
|---|---|
| German | Abo-Limits auf dem Schreibtisch. |
| Spanish | Límites de suscripción en tu escritorio. |
| Japanese | サブスクリプションの上限をデスクトップに。 |
| Simplified Chinese | 把订阅限额放在桌面上。 |


**`The exchange directory is created by the system when the widget first runs. Right-click the desktop, choose Edit Widgets, add Usage Widget for Claude Code, then come back.`**

| | |
|---|---|
| German | Das Austauschverzeichnis legt das System beim ersten Start des Widgets an. Rechtsklick auf den Schreibtisch, „Widgets bearbeiten“, Usage Widget for Claude Code hinzufügen, dann zurückkommen. |
| Spanish | El sistema crea el directorio de intercambio cuando el widget se ejecuta por primera vez. Haz clic derecho en el escritorio, elige Editar widgets, añade Usage Widget for Claude Code y vuelve aquí. |
| Japanese | 交換用ディレクトリはウィジェットの初回起動時にシステムが作成します。デスクトップを右クリックして「ウィジェットを編集」を選び、Usage Widget for Claude Code を追加してから戻ってください。 |
| Simplified Chinese | 交换目录由系统在小组件首次运行时创建。右键点击桌面，选择“编辑小组件”，添加 Usage Widget for Claude Code，然后返回。 |


**`The exporter has been modified`**

| | |
|---|---|
| German | Der Exporter wurde verändert |
| Spanish | El exportador ha sido modificado |
| Japanese | エクスポーターが変更されています |
| Simplified Chinese | 导出器已被修改 |


**`The exporter template is missing from the app bundle.`**

| | |
|---|---|
| German | Die Exporter-Vorlage fehlt im App-Bundle. |
| Spanish | Falta la plantilla del exportador en el paquete de la app. |
| Japanese | アプリバンドルにエクスポーターのテンプレートがありません。 |
| Simplified Chinese | 应用包中缺少导出器模板。 |


**`The file at ~/.claude/ccwidget-export.py is not the one this app installed. It runs on every status line redraw, so look at it before doing anything else, then reinstall a known copy.`**

| | |
|---|---|
| German | Die Datei ~/.claude/ccwidget-export.py ist nicht die, die diese App installiert hat. Sie läuft bei jedem Neuzeichnen der Statuszeile — sehen Sie sie sich zuerst an und installieren Sie dann eine bekannte Kopie. |
| Spanish | El archivo ~/.claude/ccwidget-export.py no es el que instaló esta app. Se ejecuta en cada redibujado de la línea de estado: revísalo antes de nada y luego reinstala una copia conocida. |
| Japanese | ~/.claude/ccwidget-export.py はこのアプリが入れたものではありません。ステータスライン再描画のたびに実行されるので、まず中身を確認してから、既知のコピーを入れ直してください。 |
| Simplified Chinese | ~/.claude/ccwidget-export.py 不是本应用安装的那个。它在每次状态行重绘时运行，请先查看其内容，再重新安装一份已知的副本。 |


**`The status line is not pointing at this app yet, so nothing is being written.`**

| | |
|---|---|
| German | Die Statuszeile zeigt noch nicht auf diese App, deshalb wird nichts geschrieben. |
| Spanish | La línea de estado aún no apunta a esta app, así que no se escribe nada. |
| Japanese | ステータスラインがまだこのアプリを指していないため、何も書き込まれていません。 |
| Simplified Chinese | 状态行尚未指向本应用，因此没有任何数据被写入。 |


**`The status line runs on every redraw, so the first numbers appear within seconds of the model replying.`**

| | |
|---|---|
| German | Die Statuszeile läuft bei jedem Neuzeichnen, die ersten Zahlen erscheinen also Sekunden nach der Antwort des Modells. |
| Spanish | La línea de estado se ejecuta en cada redibujado, así que los primeros números aparecen segundos después de que el modelo responda. |
| Japanese | ステータスラインは再描画のたびに実行されるため、モデルの応答から数秒で最初の数値が現れます。 |
| Simplified Chinese | 状态行在每次重绘时运行，因此模型回复后几秒内就会出现第一批数字。 |


**`The statusLine key is removed from settings.json. Other keys are untouched.`**

| | |
|---|---|
| German | Der Schlüssel statusLine wird aus settings.json entfernt. Andere Schlüssel bleiben unberührt. |
| Spanish | Se elimina la clave statusLine de settings.json. Las demás claves no se tocan. |
| Japanese | settings.json から statusLine キーを削除します。他のキーは変更しません。 |
| Simplified Chinese | 将从 settings.json 中删除 statusLine 键，其他键保持不变。 |


**`These have to be removed by hand: %@`**

| | |
|---|---|
| German | Diese müssen von Hand entfernt werden: %@ |
| Spanish | Esto hay que eliminarlo a mano: %@ |
| Japanese | これらは手動で削除してください: %@ |
| Simplified Chinese | 以下需要手动删除：%@ |


**`This widget reads the Claude Code status line, so the terminal version has to be installed and used at least once.`**

| | |
|---|---|
| German | Das Widget liest die Statuszeile von Claude Code. Die Terminalversion muss installiert und mindestens einmal benutzt worden sein. |
| Spanish | El widget lee la línea de estado de Claude Code, así que la versión de terminal debe estar instalada y usarse al menos una vez. |
| Japanese | このウィジェットは Claude Code のステータスラインを読みます。ターミナル版をインストールし、一度は使う必要があります。 |
| Simplified Chinese | 该小组件读取 Claude Code 的状态行，因此需要安装终端版并至少使用一次。 |


**`Updated %@`**

| | |
|---|---|
| German | Aktualisiert %@ |
| Spanish | Actualizado %@ |
| Japanese | 最終更新 %@ |
| Simplified Chinese | 更新于 %@ |


**`Usage Widget for Claude Code`**

| | |
|---|---|
| German | Usage Widget for Claude Code |
| Spanish | Usage Widget for Claude Code |
| Japanese | Usage Widget for Claude Code |
| Simplified Chinese | Usage Widget for Claude Code |


**`Waiting`**

| | |
|---|---|
| German | Wartet |
| Spanish | Esperando |
| Japanese | 待機中 |
| Simplified Chinese | 等待中 |


**`Waiting for Claude Code to send data. Send any message in the terminal.`**

| | |
|---|---|
| German | Warte auf Daten von Claude Code. Senden Sie eine beliebige Nachricht im Terminal. |
| Spanish | Esperando datos de Claude Code. Envía cualquier mensaje en el terminal. |
| Japanese | Claude Code からのデータを待っています。ターミナルで何かメッセージを送ってください。 |
| Simplified Chinese | 正在等待 Claude Code 发送数据。在终端中发送任意消息即可。 |


**`Watcher`**

| | |
|---|---|
| German | Beobachter |
| Spanish | Observador |
| Japanese | ウォッチャー |
| Simplified Chinese | 监视器 |


**`Week resets %@ · updated %@`**

| | |
|---|---|
| German | Wochen-Reset %@ · aktualisiert %@ |
| Spanish | Reinicio semanal %@ · actualizado %@ |
| Japanese | 週のリセット %@ · 更新 %@ |
| Simplified Chinese | 周重置 %@ · 更新于 %@ |


**`Week used`**

| | |
|---|---|
| German | Diese Woche verbraucht |
| Spanish | Consumo semanal |
| Japanese | 週の使用率 |
| Simplified Chinese | 本周已用 |


**`Working`**

| | |
|---|---|
| German | Läuft |
| Spanish | Funcionando |
| Japanese | 動作中 |
| Simplified Chinese | 运行中 |


**`~/.claude/ccwidget-export.py is deleted.`**

| | |
|---|---|
| German | ~/.claude/ccwidget-export.py wird gelöscht. |
| Spanish | Se elimina ~/.claude/ccwidget-export.py. |
| Japanese | ~/.claude/ccwidget-export.py を削除します。 |
| Simplified Chinese | 将删除 ~/.claude/ccwidget-export.py。 |


---

112 strings in total.

#!/bin/sh
# Hook de Claude Code / Codex → dynamic island (Services/Island.qml).
# Uso: island-ai-hook.sh <claude|codex> <start|stop|end|interrupt|attention|resume>
# Lee el JSON del hook por stdin (session_id, cwd, transcript_path) y avisa al
# shell por IPC en segundo plano. No imprime nada: en UserPromptSubmit la
# salida estándar se añadiría al contexto del modelo.
# En "start" busca además la ventana de Hyprland de la terminal (subiendo por
# los procesos padre) para que el clic en el notch pueda enfocarla.
agent="$1"
event="$2"
payload=$(cat)
sid=$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null)
cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null)
tp=$(printf '%s' "$payload" | jq -r '.transcript_path // ""' 2>/dev/null)
[ -n "$sid" ] || sid="$agent-$PPID"
win=""
if [ "$event" = "start" ]; then
    pids=" "
    p=$PPID
    while [ -n "$p" ] && [ "$p" -gt 1 ]; do
        pids="$pids$p "
        p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    done
    win=$(hyprctl clients -j 2>/dev/null \
        | jq -r --arg pids "$pids" '[.[] | select(.pid as $p | $pids | contains(" \($p) "))][0].address // ""' 2>/dev/null)
fi
( qs ipc call island aiEvent "$agent" "$event" "$sid" "$cwd" "$tp" "$win" >/dev/null 2>&1 & )
exit 0

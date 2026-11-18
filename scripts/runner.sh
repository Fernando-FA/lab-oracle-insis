#!/usr/bin/env bash
# Runner propio del laboratorio (WSL): ~/actions-runner-insis, etiqueta insis-db.
# Uso: scripts/runner.sh iniciar | detener | estado
set -uo pipefail
export JAVA_HOME="$HOME/.local/opt/jdk-17.0.21+9"
export PATH="$JAVA_HOME/bin:$HOME/.local/opt/sqlcl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LANG=C.UTF-8
dir="$HOME/actions-runner-insis"
pid=$(pgrep -f "$dir/bin/Runner.Listener" | head -1 || true)
case "${1:-estado}" in
  iniciar)
    [ -n "$pid" ] && { echo "ya corre (pid $pid)"; exit 0; }
    (cd "$dir" && setsid nohup ./run.sh >> "$dir/runner.log" 2>&1 < /dev/null &)
    sleep 3; echo "iniciado (log $dir/runner.log)";;
  detener)
    [ -n "$pid" ] && { pkill -f "$dir/run.sh"; kill "$pid"; echo detenido; } || echo "no corre";;
  *) [ -n "$pid" ] && echo "corre (pid $pid)" || echo detenido;;
esac

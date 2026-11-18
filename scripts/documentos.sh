#!/usr/bin/env bash
# Genera los entregables de DevSecOps en Markdown a partir de los logs de Liquibase.
#   opa → Orden de Pase Aplicativo + Procedimiento de Rollback Aplicativo (lee evidencia/plan)
#   epp → Evidencia de Pase a Producción/ambiente (lee evidencia/cd)
# Variables: AMB, TICKET, VERSION y, para epp, RESULTADO.
set -euo pipefail
raiz="$(cd "$(dirname "$0")/.." && pwd)"
tipo="${1:?opa|epp}"
mapfile -t esquemas < <(grep -vE '^\s*(#|$)' "$raiz/oracle-insis/esquemas.txt")
url="${GITHUB_SERVER_URL:-}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"

bloque() {  # título, archivo
  [ -f "$2" ] || return 0
  printf '<details><summary>%s</summary>\n\n```sql\n' "$1"
  sed -e '/^--Starting Liquibase/d' -e '/^Operation completed successfully/d' "$2"
  printf '```\n</details>\n\n'
}

pendientes() {  # esquema → "archivo::id::autor" de los changesets pendientes, en orden
  local log="$raiz/evidencia/plan/$1.status.log"
  [ -f "$log" ] && grep -oE '^\s+\S+\.sql::\S+::\S+' "$log" | sed 's/^\s*//' || true
}

changeset() {  # esquema, "archivo::id::autor", sql|rollback → texto del changeset tomado del script
  local f="${2%%::*}" id; id="${2#*::}"; id="${id%%::*}"
  awk -v id="$id" -v modo="$3" '
    /^--changeset / { split($2, a, ":"); dentro = (a[2] == id); next }
    !dentro || /^--liquibase/ { next }
    modo == "rollback" && /^--rollback / { sub(/^--rollback /, ""); print; next }
    modo == "sql" && !/^--rollback/ && NF { print }
  ' "$raiz/oracle-insis/migrations/$1/$f"
}

cabecera() {
  cat <<MD
| Campo | Valor |
| --- | --- |
| Ticket Ivanti | ${TICKET} |
| Ambiente | ${AMB} |
| Versión / etiqueta | ${VERSION} / \`${AMB}-v${VERSION}\` |
| Commit | \`${GITHUB_SHA:-$(git -C "$raiz" rev-parse HEAD)}\` |
| Ejecutor | ${GITHUB_ACTOR:-$USER} |
| Fecha | $(date '+%Y-%m-%d %H:%M %Z') |
| Ejecución | ${url} |

MD
}

case "$tipo" in
  opa)
    echo "## OPA · Orden de Pase Aplicativo — INSIS BD ${AMB} v${VERSION}"
    echo; cabecera
    echo "### Cambios que se ejecutan (orden de ejecución)"; echo
    for e in "${esquemas[@]}"; do
      mapfile -t pend < <(pendientes "$e")
      [ ${#pend[@]} -eq 0 ] && { echo "- **$e**: sin cambios"; continue; }
      echo "#### $e"; echo
      for cs in "${pend[@]}"; do
        printf '`%s`\n\n```sql\n' "$cs"; changeset "$e" "$cs" sql; printf '```\n\n'
      done
    done
    echo "## PRA · Procedimiento de Rollback Aplicativo"; echo
    echo "Automático con \`gha-prod-insis-db-rollback\` a la etiqueta anterior. SQL que deshace este pase (orden inverso):"; echo
    for ((i=${#esquemas[@]}-1; i>=0; i--)); do
      e=${esquemas[$i]}
      mapfile -t pend < <(pendientes "$e" | tac)
      [ ${#pend[@]} -eq 0 ] && continue
      echo "#### $e"; echo
      for cs in "${pend[@]}"; do
        printf '`%s`\n\n```sql\n' "$cs"; changeset "$e" "$cs" rollback; printf '```\n\n'
      done
    done
    echo "Logs completos de Liquibase (update-sql, future-rollback-sql) en el artefacto de la ejecución."
    ;;
  epp)
    echo "## EPP · Evidencia del pase — INSIS BD ${AMB} v${VERSION}: ${RESULTADO:-desconocido}"
    echo; cabecera
    for e in "${esquemas[@]}"; do
      bloque "$e · update" "$raiz/evidencia/cd/$e.update.log"
      bloque "$e · estado final" "$raiz/evidencia/cd/$e.status.log"
    done
    ;;
esac

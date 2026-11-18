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
    echo "### Cambios pendientes por esquema (orden de ejecución)"; echo
    for e in "${esquemas[@]}"; do bloque "$e · pendientes" "$raiz/evidencia/plan/$e.status.log"; done
    echo "### SQL que se ejecutará"; echo
    for e in "${esquemas[@]}"; do bloque "$e · update-sql" "$raiz/evidencia/plan/$e.update-sql.log"; done
    echo "## PRA · Procedimiento de Rollback Aplicativo"; echo
    echo "Rollback automático: \`gha-prod-insis-db-rollback\` con la etiqueta anterior. SQL que deshace este pase (orden inverso de esquemas):"; echo
    for ((i=${#esquemas[@]}-1; i>=0; i--)); do e=${esquemas[$i]}; bloque "$e · rollback" "$raiz/evidencia/plan/$e.future-rollback-sql.log"; done
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

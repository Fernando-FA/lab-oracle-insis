#!/usr/bin/env bash
# Ejecuta un comando de Liquibase (SQLcl) en cada esquema de INSIS, entrando por proxy con INSIS_DEPLOY.
# Uso: scripts/lb.sh <desa|test|prod> <comando> [argumentos de liquibase]
#   comandos: validate | status | update | update-sql | future-rollback-sql | tag <t> | rollback <t> | rollback-sql <t>
# Variables: INSIS_DEPLOY_PASSWORD (obligatoria), LB_DIR (carpeta con un subdirectorio por esquema;
# por defecto oracle-insis/migrations), LB_SALIDA (carpeta donde dejar el log de cada esquema).
set -euo pipefail
raiz="$(cd "$(dirname "$0")/.." && pwd)"
amb="${1:?ambiente}"; cmd="${2:?comando}"; shift 2
env_file="$raiz/oracle-insis/environment/.env.$amb"
[ -f "$env_file" ] || { echo "No existe $env_file" >&2; exit 2; }
# shellcheck disable=SC1090
source "$env_file"
: "${INSIS_DEPLOY_PASSWORD:?falta INSIS_DEPLOY_PASSWORD}"
lb_dir="${LB_DIR:-$raiz/oracle-insis/migrations}"
salida="${LB_SALIDA:-$raiz/evidencia/$amb}"
mkdir -p "$salida"

mapfile -t esquemas < <(grep -vE '^\s*(#|$)' "$raiz/oracle-insis/esquemas.txt")
[[ "$cmd" == rollback* ]] && mapfile -t esquemas < <(printf '%s\n' "${esquemas[@]}" | tac)

case "$cmd" in
  tag)      args="-tag $1" ;;
  rollback|rollback-sql) args="-tag $1 -changelog-file changelog.xml" ;;
  validate|status|update|update-sql|future-rollback-sql) args="-changelog-file changelog.xml $*" ;;
  *) echo "Comando no soportado: $cmd" >&2; exit 2 ;;
esac
[ "$cmd" = status ] && args="$args -verbose"

conectar() { echo "connect $DB_USER[$1]/\"$INSIS_DEPLOY_PASSWORD\"@//$DB_HOST:$DB_PORT/$DB_SERVICE"; }

# Liquibase guarda la etiqueta en la última fila aplicada: si un esquema no tuvo cambios entre dos versiones, la
# etiqueta nueva pisa a la anterior. Volver a la etiqueta pisada equivale a volver a la menor etiqueta posterior que
# quedó en ese esquema (mismo estado). Supone que la etiqueta pedida sí se aplicó en el ambiente: lo verifica el
# workflow de rollback contra los despliegues registrados en GitHub.
etiqueta_efectiva() {  # esquema, etiqueta pedida
  local tags
  tags=$(sql -S -L /nolog <<SQL | tr -d '\r' | sed 's/[[:space:]]*$//' | grep -E '^[a-z]+-v[0-9]' || true
$(conectar "$1")
set heading off feedback off pagesize 0
select tag from databasechangelog where tag is not null;
exit
SQL
)
  if grep -qx "$2" <<<"$tags"; then echo "$2"; return; fi
  local prefijo="${2%%-v*}-v"
  printf '%s\n%s\n' "$tags" "$2" | grep "^$prefijo" | sort -V | grep -A1 -x "$2" | sed -n 2p
}

fallo=0
for esq in "${esquemas[@]}"; do
  dir="$lb_dir/$esq"
  if [ ! -f "$dir/changelog.xml" ]; then echo "== $esq: sin changelog.xml, se omite"; continue; fi
  log="$salida/$esq.$cmd.log"
  args_esq="$args"
  if [[ "$cmd" == rollback* ]]; then
    efectiva=$(etiqueta_efectiva "$esq" "$1")
    if [ -z "$efectiva" ]; then echo "!! $esq: la etiqueta $1 no se aplicó en este ambiente" >&2; fallo=1; break; fi
    [ "$efectiva" != "$1" ] && echo "   $1 quedó registrada como $efectiva en $esq (sin cambios entre ambas)"
    args_esq="-tag $efectiva -changelog-file changelog.xml"
  fi
  echo "== $amb · $esq · liquibase $cmd"
  sql -S -L /nolog > "$log" 2>&1 <<SQL || true
$(conectar "$esq")
cd $dir
liquibase $cmd $args_esq
exit
SQL
  sed -e '/^--Starting Liquibase/d' "$log"
  if ! grep -q 'Operation completed successfully' "$log"; then
    echo "!! $esq: liquibase $cmd falló (log: $log)" >&2
    fallo=1
    break
  fi
done
exit $fallo

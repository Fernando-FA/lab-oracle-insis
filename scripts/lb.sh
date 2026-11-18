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
  tag)                   nueva="$1"; cmd=update; args="" ;;
  rollback|rollback-sql) args="-tag $1" ;;
  validate|status|update|update-sql|future-rollback-sql) args="$*" ;;
  *) echo "Comando no soportado: $cmd" >&2; exit 2 ;;
esac
[ "$cmd" = status ] && args="$args -verbose true"
accion="${nueva:+tag}"; accion="${accion:-$cmd}"

conectar() { echo "connect $DB_USER[$1]/\"$INSIS_DEPLOY_PASSWORD\"@//$DB_HOST:$DB_PORT/$DB_SERVICE"; }

# Cada etiqueta de despliegue es su propia fila en DATABASECHANGELOG: un changeset tagDatabase (autor "pipeline").
# El comando "liquibase tag" de Liquibase la escribiría en la última fila aplicada, y esa fila se pisa cuando un
# esquema no tiene cambios o cuando se reaplica un script runOnChange (code/): el rollback a esa etiqueta no haría nada.
# La envoltura incluye el changelog del esquema más las etiquetas ya registradas en la base (y la nueva, si se pide),
# para que Liquibase las conozca al hacer rollback. Liquibase también deshace la fila de la etiqueta destino: tras un
# rollback se vuelve a registrar, para que la base quede marcada con la versión a la que volvió.
envoltura() {  # esquema, carpeta → escribe <carpeta>/.lb-<amb>.xml
  local etiquetas
  etiquetas=$(sql -S -L /nolog <<SQL | tr -d '\r' | sed 's/[[:space:]]*$//' | grep -E '^[a-z]+-v[0-9]' || true
$(conectar "$1")
set heading off feedback off pagesize 0
whenever sqlerror continue
select id from databasechangelog where author = 'pipeline' order by orderexecuted;
exit
SQL
)
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<databaseChangeLog xmlns="http://www.liquibase.org/xml/ns/dbchangelog"'
    echo '    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-latest.xsd">'
    [ -z "${solo_etiquetas:-}" ] && echo '  <include file="changelog.xml" relativeToChangelogFile="true"/>'
    for t in $etiquetas ${nueva:-}; do
      echo "  <changeSet id=\"$t\" author=\"pipeline\" logicalFilePath=\"pipeline/etiquetas\"><tagDatabase tag=\"$t\"/></changeSet>"
    done
    echo '</databaseChangeLog>'
  } | awk '!visto[$0]++' > "$2/.lb-$amb.xml"
}

fallo=0
for esq in "${esquemas[@]}"; do
  dir="$lb_dir/$esq"
  if [ ! -f "$dir/changelog.xml" ]; then echo "== $esq: sin changelog.xml, se omite"; continue; fi
  log="$salida/$esq.$accion.log"
  envoltura "$esq" "$dir"
  echo "== $amb · $esq · liquibase $accion ${nueva:-${1:-}}"
  sql -S -L /nolog > "$log" 2>&1 <<SQL || true
$(conectar "$esq")
cd $dir
liquibase $cmd $args -changelog-file .lb-$amb.xml
exit
SQL
  sed -e '/^--Starting Liquibase/d' "$log"
  if ! grep -q 'Operation completed successfully' "$log"; then
    echo "!! $esq: liquibase $accion falló (log: $log)" >&2
    fallo=1
    break
  fi
  if [ "$cmd" = rollback ]; then
    # Solo la etiqueta: con el changelog completo, el update volvería a aplicar lo que se acaba de deshacer.
    nueva="$1" solo_etiquetas=1 envoltura "$esq" "$dir"
    sql -S -L /nolog > "$salida/$esq.retag.log" 2>&1 <<SQL || true
$(conectar "$esq")
cd $dir
liquibase update -changelog-file .lb-$amb.xml
exit
SQL
    grep -q 'Operation completed successfully' "$salida/$esq.retag.log" && echo "   $esq: etiqueta $1 registrada de nuevo" \
      || { echo "!! $esq: no se pudo volver a registrar $1" >&2; fallo=1; break; }
  fi
done
exit $fallo

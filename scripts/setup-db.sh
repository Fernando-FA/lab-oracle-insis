#!/usr/bin/env bash
# Prepara la base del laboratorio: PDBs DESA/TEST/PROD, esquemas que imitan INSIS, INSIS_DEPLOY con proxy
# y la "instalación del proveedor" (tablas base + filas en DATABASECHANGELOG de cada esquema).
set -euo pipefail
raiz="$(cd "$(dirname "$0")/.." && pwd)"
set -a; source "$raiz/.env"; set +a
c=lab-oracle-insis
docker exec "$c" bash -c 'sqlplus -S / as sysdba @/setup/01_pdbs.sql'
for pdb in DESA TEST PROD; do
  docker exec -e PDB="$pdb" -e PW="$INSIS_DEPLOY_PASSWORD" "$c" bash -c \
    'sqlplus -S / as sysdba <<SQL
ALTER SESSION SET CONTAINER = $PDB;
@/setup/02_esquemas.sql "$PW"
SQL'
done
for amb in desa test prod; do
  LB_DIR="$raiz/db/setup/fadata-changelog" LB_SALIDA="$raiz/evidencia/setup/$amb" \
    "$raiz/scripts/lb.sh" "$amb" update
done

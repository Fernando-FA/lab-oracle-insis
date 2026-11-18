# lab-oracle-insis

Ejemplo práctico del versionamiento y despliegue de cambios de BD de INSIS alineado al lineamiento DevSecOps de
Pacífico Salud: ramas por ambiente (`desa` → `test` → `prod`), etiquetas en `test` y `prod`, un workflow por ambiente
y aprobaciones por PR y por environment. El motor es **Liquibase** (incluido en SQLcl), que usa la tabla
`DATABASECHANGELOG` que ya existe en cada esquema de INSIS.

## Estructura

```
.github/
  workflows/
    gha-pr-insis-db-validate.yml      compuerta de PRs (promoción entre ramas, nomenclatura, plan en desa)
    gha-desa-insis-db-deploy.yml      despliegue automático al integrar en desa
    gha-test-insis-db-deploy.yml      merge → etiqueta test-vX.Y.Z · Run workflow (ticket) → CI → aprobación → CD
    gha-prod-insis-db-deploy.yml      merge → etiqueta prod-vX.Y.Z · Run workflow (ticket) → CI → aprobación → CD
    gha-prod-insis-db-rollback.yml    vuelve prod a una etiqueta anterior
    gha-shared-insis-db-deploy.yml    pasos comunes de test y prod
  CODEOWNERS                          dueños por esquema, DDL y pipeline
oracle-insis/
  VERSION                             versión de la entrega (da nombre a las etiquetas)
  esquemas.txt                        orden de despliegue de los esquemas
  environment/.env.{desa,test,prod}   conexión por ambiente (sin claves)
  migrations/<ESQUEMA>/
    changelog.xml                     scripts del esquema en orden de ejecución
    tables/V<n>.<m>_<US>-<desc>.sql   DDL
    scripts/V<n>.<m>_<US>-<desc>.sql  DML / configuración
    code/R_<OBJETO>.sql               paquetes, vistas: se reaplican si cambian
scripts/                              lb.sh (Liquibase por esquema) · validar.py · documentos.sh (OPA, PRA, EPP)
db/setup/                             base del laboratorio: PDBs DESA/TEST/PROD, esquemas, INSIS_DEPLOY por proxy
```

## Un script

```sql
--liquibase formatted sql

--changeset fernando:V1.1-1
ALTER TABLE CFG_COVER ADD (COPAY_PCT NUMBER(5,2));
--rollback ALTER TABLE CFG_COVER DROP COLUMN COPAY_PCT;
```

Reglas de la compuerta: primera línea `--liquibase formatted sql`; cada changeset con `--rollback`; el id empieza con
la versión del archivo; el archivo está en el `changelog.xml` del esquema; un script ya integrado no se modifica;
sin `GRANT`, `CREATE/ALTER/DROP USER` ni `ALTER SYSTEM`.

## Flujo y aprobaciones

| Paso | Quién | Aprobación (Pacífico) | En GitHub |
| --- | --- | --- | --- |
| PR `feature/feat-<user>` → `desa` | Desarrollador | Soluciones de Negocio + Desarrollo + dueño del esquema | Protección de `desa` + CODEOWNERS |
| Merge en `desa` | Automático | — | `gha-desa` (environment `desa`) |
| PR `desa` → `test` | Desarrollador | Infra-DBA + Calidad | Protección de `test` |
| Despliegue en test | Ing. DevSecOps (ticket Ivanti) | Calidad | Environment `test` |
| PR `test` → `prod` | Desarrollador | Soluciones de Negocio + Seguridad | Protección de `prod` + la compuerta exige `test-vX.Y.Z` desplegada |
| Despliegue en prod | Ing. DevSecOps (ticket Ivanti) | Soluciones de Negocio | Environment `prod` |

En el laboratorio un único usuario cumple todos los roles: los PR exigen la compuerta pero 0 revisiones (no se puede
aprobar un PR propio) y los environments `test` y `prod` tienen como revisor al mismo usuario.

## Base local

```bash
cp .env.example .env           # completar claves
docker compose up -d
scripts/setup-db.sh            # PDBs, esquemas y "instalación del proveedor"
```

# lab-oracle-insis

Ejemplo práctico del versionamiento y despliegue de cambios de BD de INSIS alineado al lineamiento DevSecOps de
Pacífico Salud: ramas por ambiente (`desa` → `test` → `prod`), etiquetas en `test` y `prod`, un workflow por ambiente
y aprobaciones por PR y por environment. El motor es **Liquibase** (incluido en SQLcl), que usa la tabla
`DATABASECHANGELOG` que ya existe en cada esquema de INSIS.

Este repo tiene solo lo que es del equipo de BD: los scripts de migración y la configuración de ambientes. Los
workflows son llamadas de pocas líneas a las plantillas de DevSecOps
([lab-devsecops-pipelines-bd](https://github.com/Fernando-FA/lab-devsecops-pipelines-bd), versión fija `@v1`), donde
viven la compuerta, el despliegue y los scripts: un PR de este repo no puede cambiar la validación que debe pasar.

## Estructura

```
.github/
  workflows/                          llamadas a las plantillas de DevSecOps (@v1)
    gha-pr-insis-db-validate.yml      compuerta de PRs (promoción entre ramas, nomenclatura, plan en desa)
    gha-desa-insis-db-deploy.yml      despliegue automático al integrar en desa
    gha-test-insis-db-deploy.yml      merge → etiqueta test-vX.Y.Z · Run workflow (ticket) → CI → aprobación → CD
    gha-prod-insis-db-deploy.yml      merge → etiqueta prod-vX.Y.Z · Run workflow (ticket) → CI → aprobación → CD
    gha-prod-insis-db-rollback.yml    vuelve prod a una etiqueta anterior
  CODEOWNERS                          dueños por esquema, DDL y workflows
oracle-insis/
  esquemas.txt                        orden de despliegue de los esquemas
  environment/.env.{desa,test,prod}   conexión por ambiente (sin claves)
  migrations/<ESQUEMA>/
    changelog.xml                     scripts del esquema en orden de ejecución
    tables/V<n>.<m>_<US>-<desc>.sql   DDL
    scripts/V<n>.<m>_<US>-<desc>.sql  DML / configuración
    code/R_<OBJETO>.sql               paquetes, vistas: se reaplican si cambian
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
sin `GRANT`, `CREATE/ALTER/DROP USER` ni `ALTER SYSTEM`. En `code/` (runOnChange) el `--rollback` debe contener la
versión anterior del objeto: al cambiar el script se actualizan juntos.

## Etiquetas

- **Git:** la versión la asigna el pipeline, nadie la edita. Al integrar en `test` se crea la siguiente `test-vX.Y.0`
  (sube el menor); al integrar en `prod` se crea `prod-vX.Y.0` con el número de la etiqueta de test que tiene el mismo
  contenido, y falla si no hay ninguna. La compuerta y el despliegue de `prod` exigen además que esa etiqueta de test
  se haya desplegado bien.
- **Base:** cada despliegue registra en cada esquema una fila `tagDatabase` con el mismo nombre (autor `pipeline`,
  archivo `pipeline/etiquetas`). No se usa `liquibase tag`, que escribe en la última fila aplicada y se pierde cuando
  un esquema no tiene cambios o se reaplica un script de `code/`. `gha-prod-insis-db-rollback` vuelve a esa fila.

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

## Laboratorio

La base Oracle con las PDBs DESA/TEST/PROD y el runner están en
[lab-insis-entorno](https://github.com/Fernando-FA/lab-insis-entorno); en Pacífico esas piezas ya existen.

#!/usr/bin/env python3
"""Compuerta de PRs: nomenclatura, estructura y reglas de los scripts de Liquibase.

Uso: validar.py <rama-base>   (compara contra origin/<rama-base>)
"""
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
MIG = RAIZ / "oracle-insis" / "migrations"
NOMBRE = {
    "tables": re.compile(r"^V(\d+)\.(\d+)_[A-Za-z0-9]+(-[A-Za-z0-9]+)*\.sql$"),
    "scripts": re.compile(r"^V(\d+)\.(\d+)_[A-Za-z0-9]+(-[A-Za-z0-9]+)*\.sql$"),
    "code": re.compile(r"^R_[A-Z0-9_]+\.sql$"),
}
PROHIBIDO = re.compile(r"\b(GRANT|REVOKE|DROP\s+USER|CREATE\s+USER|ALTER\s+USER|ALTER\s+SYSTEM|CONNECT\s+\w+/)\b", re.I)
errores: list[str] = []


def error(archivo, msg):
    errores.append(f"{archivo}: {msg}")


def esquemas():
    txt = (RAIZ / "oracle-insis" / "esquemas.txt").read_text()
    return [l.strip() for l in txt.splitlines() if l.strip() and not l.startswith("#")]


def revisar_sql(ruta: Path, carpeta: str):
    rel = ruta.relative_to(RAIZ)
    lineas = ruta.read_text(encoding="utf-8").splitlines()
    if not lineas or not lineas[0].startswith("--liquibase formatted sql"):
        error(rel, "la primera línea debe ser '--liquibase formatted sql'")
    m = NOMBRE[carpeta].match(ruta.name)
    version = f"V{m.group(1)}.{m.group(2)}" if m and carpeta != "code" else None
    changesets = []  # [id, tiene_rollback, atributos]
    for l in lineas:
        cs = re.match(r"--changeset\s+([^:\s]+):(\S+)(.*)", l)
        if cs:
            changesets.append([cs.group(2), False, cs.group(3)])
        elif l.startswith("--rollback") and changesets:
            changesets[-1][1] = True
        elif PROHIBIDO.search(l) and not l.lstrip().startswith("--"):
            error(rel, f"sentencia no permitida: {l.strip()}")
    if not changesets:
        error(rel, "no tiene ningún --changeset")
    for cid, rb, attrs in changesets:
        if not rb:
            error(rel, f"el changeset {cid} no tiene --rollback")
        if version and not cid.startswith(version):
            error(rel, f"el id del changeset ({cid}) debe empezar con la versión del archivo ({version})")
        if carpeta == "code" and "runOnChange:true" not in attrs:
            error(rel, f"el changeset {cid} de code/ debe llevar runOnChange:true")


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else "desa"
    validos = esquemas()
    for d in sorted(p for p in MIG.iterdir() if p.is_dir()):
        if d.name not in validos:
            error(d.relative_to(RAIZ), "esquema no declarado en oracle-insis/esquemas.txt")
            continue
        cl = d / "changelog.xml"
        if not cl.exists():
            error(d.relative_to(RAIZ), "falta changelog.xml")
            continue
        ns = {"lb": "http://www.liquibase.org/xml/ns/dbchangelog"}
        incluidos = [i.get("file") for i in ET.parse(cl).getroot().findall("lb:include", ns)]
        for inc in incluidos:
            if not (d / inc).exists():
                error(cl.relative_to(RAIZ), f"incluye {inc}, que no existe")
        for f in sorted(d.rglob("*")):
            if f.is_dir() or f.name == "changelog.xml" or f.name.startswith("."):
                continue
            rel = f.relative_to(d)
            carpeta = rel.parts[0] if len(rel.parts) == 2 else None
            if carpeta not in NOMBRE or not NOMBRE[carpeta].match(f.name):
                error(f.relative_to(RAIZ), "ubicación o nombre inválido: <ESQUEMA>/{tables,scripts}/V<n>.<m>_<US>-<desc>.sql o <ESQUEMA>/code/R_<OBJETO>.sql")
                continue
            if str(rel) not in incluidos:
                error(f.relative_to(RAIZ), "no está incluido en changelog.xml")
            revisar_sql(f, carpeta)
        versiones = [Path(i).name.split("_")[0] for i in incluidos if not Path(i).name.startswith("R_")]
        if len(versiones) != len(set(versiones)):
            error(cl.relative_to(RAIZ), "hay versiones repetidas")

    # Un script ya integrado no se modifica: el cambio va en un script nuevo (salvo code/, que se reaplica).
    diff = subprocess.run(["git", "diff", "--name-status", f"origin/{base}...HEAD", "--", "oracle-insis/migrations"],
                          cwd=RAIZ, capture_output=True, text=True, check=True).stdout
    for linea in diff.splitlines():
        estado, ruta = linea.split("\t")[0], linea.split("\t")[-1]
        if estado[0] in "MDR" and ruta.endswith(".sql") and "/code/" not in ruta:
            error(ruta, f"un script ya integrado en {base} no se puede modificar ni borrar ({estado}); crea uno nuevo")

    if errores:
        print("Compuerta: RECHAZADO")
        for e in errores:
            print(f"  - {e}")
        return 1
    print("Compuerta: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())

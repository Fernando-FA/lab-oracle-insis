#!/usr/bin/env bash
# Versión de las entregas, calculada a partir de las etiquetas de Git (requiere las etiquetas descargadas).
#   version.sh siguiente          → la versión que corresponde a la próxima entrega a test (sube el menor)
#   version.sh de <amb> <commit>  → la versión de la etiqueta <amb>-v* que apunta a ese commit
#   version.sh certificada <commit> → la versión de la etiqueta test-v* con el mismo contenido que ese commit
set -euo pipefail
ultimas() { git tag -l "$1-v*" --sort=-v:refname; }
case "${1:?siguiente|de|certificada}" in
  siguiente)
    ultima=$(ultimas test | head -1)
    if [ -z "$ultima" ]; then echo 1.0.0; exit 0; fi
    IFS=. read -r ma mi _ <<<"${ultima#test-v}"
    echo "$ma.$((mi + 1)).0" ;;
  de)
    for t in $(ultimas "$2"); do
      [ "$(git rev-parse "$t^{commit}")" = "$(git rev-parse "$3^{commit}")" ] && { echo "${t#"$2"-v}"; exit 0; }
    done
    exit 1 ;;
  certificada)
    arbol=$(git rev-parse "$2^{tree}")
    for t in $(ultimas test); do
      [ "$(git rev-parse "$t^{tree}")" = "$arbol" ] && { echo "${t#test-v}"; exit 0; }
    done
    exit 1 ;;
esac

#!/usr/bin/env bash
set -euo pipefail

readonly VERSION="0.1.0"

main() {
  echo "ZorinTrim v${VERSION}"

  if ! command -v apt >/dev/null 2>&1; then
    echo "Error: ZorinTrim requires an apt-based system (Zorin OS 18.1)." >&2
    exit 1
  fi

  echo "No debloating actions are implemented yet."
}

main "$@"

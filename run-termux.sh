#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $# -lt 1 ]]; then
  echo "Uso: ./run-termux.sh /ruta/miniarino-amd64.img[.gz]" >&2
  exit 2
fi
INPUT="$1"
[[ -f "$INPUT" ]] || { echo "No existe el archivo: $INPUT" >&2; exit 1; }
INPUT_DIR="$(cd "$(dirname "$INPUT")" && pwd)"
INPUT="$INPUT_DIR/$(basename "$INPUT")"
if [[ "$INPUT" == *.gz ]]; then
  OUTPUT="${INPUT%.gz}"
  if [[ ! -f "$OUTPUT" ]]; then
    TMP="$OUTPUT.part"
    [[ ! -e "$TMP" ]] || { echo "Ya existe un archivo parcial: $TMP; revísalo antes de continuar." >&2; exit 1; }
    echo "Expandiendo imagen de forma dispersa; reserva espacio para 16 GiB lógicos."
    gzip -dc -- "$INPUT" | dd of="$TMP" bs=4M conv=sparse status=progress
    mv -- "$TMP" "$OUTPUT"
  fi
  INPUT="$OUTPUT"
fi
DIR="$(cd "$(dirname "$0")" && pwd)"
RAM="${RAM:-2048}" SMP="${SMP:-2}" QEMU_DISPLAY="${QEMU_DISPLAY:-sdl}" \
  "$DIR/scripts/run-qemu.sh" "$INPUT"

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
    for cmd in gzip dd; do
      command -v "$cmd" >/dev/null 2>&1 || { echo "Falta $cmd para expandir la imagen .gz." >&2; exit 1; }
    done
    if ! printf '' | dd of=/dev/null bs=1 conv=sparse >/dev/null 2>&1; then
      echo "La versión de dd no admite conv=sparse; actualiza coreutils antes de expandir para evitar ocupar hasta 16 GiB." >&2
      exit 1
    fi
    TMP="$OUTPUT.part"
    [[ ! -e "$TMP" ]] || { echo "Ya existe un archivo parcial: $TMP; revísalo antes de continuar." >&2; exit 1; }
    echo "Expandiendo imagen de forma dispersa; reserva espacio para 16 GiB lógicos."
    gzip -dc -- "$INPUT" | dd of="$TMP" bs=4M conv=sparse status=progress
    mv -- "$TMP" "$OUTPUT"
  fi
  INPUT="$OUTPUT"
fi
DIR="$(cd "$(dirname "$0")" && pwd)"
RAM="${RAM:-2048}" SMP="${SMP:-2}" QEMU_DISPLAY="${QEMU_DISPLAY:-auto}" \
QEMU_USB_INPUT="${QEMU_USB_INPUT:-auto}" \
  "$DIR/scripts/run-qemu.sh" "$INPUT"

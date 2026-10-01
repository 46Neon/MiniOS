# Referencia Debian 13 amd64

Referencia declarada para el sistema que debe preservarse:

- GitHub Actions run: `36923712230`
- Artifact: `miniarino-debian13-amd64-67f14b454992143184f4c097ba0b68fbada230ab`
- Página del run: `https://github.com/46Neon/MiniOS/actions/runs/36923712230`
- SHA textual incluido en el nombre del artifact: `67f14b454992143184f4c097ba0b68fbada230ab`

Este repositorio de trabajo no contiene una copia local verificable de la imagen.
El SHA anterior se registra tal como aparece en el nombre proporcionado; no se
presenta como SHA criptográfico de los bytes de la imagen. La referencia a un
run/artifact no es un backup permanente: Actions tiene retención temporal y el
artifact puede expirar. No se ha sobrescrito ni eliminado el artifact y no se
ha añadido una imagen de 16 GiB al historial Git.

La nueva vía `baremetal32/` deberá crear una imagen independiente x86-32 para
BIOS/SeaBIOS/QEMU con disco IDE. No debe alterar la imagen Debian amd64 ni el
sistema principal existente.

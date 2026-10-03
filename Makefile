SHELL := /bin/bash
IMAGE := build/os.img

.PHONY: all help native-help termux-native-check termux-native-install termux-native-chromium \
        termux-native-start termux-native-stop termux-native-doctor \
        termux-native-profile test test-termux-native image verify run debug \
        selftest test-qemu-runner clean legacy-image legacy-verify legacy-run legacy-debug

# Deliberately safe default: print native-first guidance; do not build an image,
# install packages, or launch a GUI as a side effect of plain `make`.
.DEFAULT_GOAL := help
all: help

help native-help:
	@printf '%s\n' \
	  'MiniAriño — Termux + Termux:X11 (propuesta local; requiere prueba en Android)' \
	  '' \
	  '  make termux-native-check    Inspección sin instalar paquetes' \
	  '  make termux-native-install  Instalación opt-in; solicita confirmación en Termux' \
	  '  make termux-native-chromium Instalar Chromium opcional en XFCE (Termux)' \
	  '  make termux-native-doctor   Diagnóstico de solo lectura' \
	  '  make termux-native-profile Aplicar perfil móvil aislado y reversible' \
	  '  make termux-native-start    Iniciar XFCE en Termux:X11' \
	  '  make termux-native-stop     Detener la sesión administrada' \
	  '  make test                  Pruebas locales seguras (sin Android GUI)' \
	  '' \
	  '  make legacy-image / legacy-verify / legacy-run  Ruta Debian/QEMU manual heredada' \
	  '  make clean                               Limpiar temporales heredados (no borra os.img)'

# Current product path: native packages in Termux, displayed by the local
# Termux:X11 Android app. No distro, PRoot, QEMU, APK, or network server.
termux-native-check:
	./scripts/termux-native/install.sh --check

termux-native-install:
	./scripts/termux-native/install.sh --install

termux-native-chromium:
	./scripts/termux-native/install.sh --install-chromium

termux-native-start:
	./scripts/termux-native/start.sh

termux-native-stop:
	./scripts/termux-native/stop.sh

termux-native-doctor:
	./scripts/termux-native/doctor.sh

termux-native-profile:
	./scripts/termux-native/mobile-profile.sh --apply

test: test-termux-native

test-termux-native:
	bash ./tests/test-termux-native.sh

# Kept for maintainers who explicitly work on the archived image builder.
# These targets are never prerequisites of the default target.
legacy-image image:
	mkdir -p build
	./scripts/build-image.sh "$(IMAGE)"

legacy-verify verify:
	./scripts/verify-image.sh "$(IMAGE)"

legacy-run run: legacy-verify
	./scripts/run-qemu.sh "$(IMAGE)"

legacy-debug debug: legacy-verify
	DEBUG=1 ./scripts/run-qemu.sh "$(IMAGE)"

selftest:
	./scripts/miniarino-selftest.sh

test-qemu-runner:
	./tests/test-run-qemu.sh
	bash ./tests/test-display-mode.sh

# Remove only disposable image-builder work files; preserve any final image.
clean:
	./scripts/clean-build.sh

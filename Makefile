SHELL := /bin/bash
IMAGE := build/os.img

.PHONY: all help native-help termux-native-check termux-native-install termux-native-chromium termux-native-blender \
        termux-native-start termux-native-stop termux-native-doctor \
        termux-native-profile test test-termux-native image verify run debug \
        selftest test-qemu-runner clean legacy-image legacy-verify legacy-run legacy-debug

# Safe default: help only. In particular, plain `make` never creates the
# historical multi-GiB image, installs packages, builds an APK, or launches a GUI.
.DEFAULT_GOAL := help
all: help

help native-help:
	@printf '%s\n' \
	  'MiniAriño — escritorio Linux objetivo en una sola APK Android' \
	  '' \
	  '  Desarrollo APK: consulta android/README.md y docs/APK_DESKTOP_ROADMAP.md' \
	  '  make test                  Pruebas host-safe heredadas; no validan Android/XFCE' \
	  '' \
	  '  Objetivos preservados (no son el producto APK):' \
	  '  make termux-native-check    Inspección Termux sin instalar paquetes' \
	  '  make termux-native-install  Instalación opt-in; solicita confirmación' \
	  '  make termux-native-chromium Instalar Chromium opcional en Termux/XFCE' \
	  '  make termux-native-blender  Instalar Blender experimental (TUR, opt-in)' \
	  '  make termux-native-doctor   Diagnóstico de solo lectura' \
	  '  make termux-native-profile Perfil móvil Termux/XFCE opt-in y reversible' \
	  '  make termux-native-start/stop Controlar sesión Termux/X11 heredada' \
	  '' \
	  '  Ruta de imagen Debian/QEMU heredada y manual:' \
	  '  make legacy-image / legacy-verify / legacy-run' \
	  '  make clean                               Limpiar temporales; no borra os.img'

# Preserved experimental scripts for a separate Termux/X11 path. They are not
# the standalone APK product and are never invoked by the default target.
termux-native-check:
	./scripts/termux-native/install.sh --check

termux-native-install:
	./scripts/termux-native/install.sh --install

termux-native-chromium:
	./scripts/termux-native/install.sh --install-chromium

termux-native-blender:
	./scripts/termux-native/install.sh --install-blender

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

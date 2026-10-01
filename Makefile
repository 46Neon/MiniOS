SHELL := /bin/bash
IMAGE := build/os.img

.PHONY: all image verify run debug selftest clean
all: image

# The image is intentionally rebuilt on every invocation, including after clean.
image:
	mkdir -p build
	./scripts/build-image.sh "$(IMAGE)"

verify:
	./scripts/verify-image.sh "$(IMAGE)"

run: verify
	./scripts/run-qemu.sh "$(IMAGE)"

debug: verify
	DEBUG=1 ./scripts/run-qemu.sh "$(IMAGE)"

# Run from a logged-in, unprivileged XFCE terminal inside MiniAriño.
selftest:
	./scripts/miniarino-selftest.sh

# Preserve any existing os.img; remove only disposable build work files.
clean:
	./scripts/clean-build.sh

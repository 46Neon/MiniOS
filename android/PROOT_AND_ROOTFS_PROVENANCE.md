# ARM64 PRoot and Debian rootfs provenance

The build stages only the ARM64 PRoot runtime files needed by the APK. The source package/build metadata commits and package archive SHA-256 values are fixed in `scripts/fetch_proot_runtime.py`; that script verifies each Debian archive's digest and `aarch64` package architecture, then verifies the ELF machine type before copying files to APK assets. No `latest` URL or third-party mirror binary is used.

| Component | Version / source commit | License | Termux package archive SHA-256 |
| --- | --- | --- | --- |
| PRoot | 5.1.107.96; `termux/termux-packages` commit `de39661946f7e8175b5dd0755121fa28cb0aebd1`; upstream source archive SHA-256 `75f654fe60dea92dabff2bf083ae8bfe4f91baa6a1a374786a6bf391015eebaa` | GPL-2.0 | `8199dca06dccb693ec09fb1759e3e1ad08b4863f0c11c612f89c20bd9ecdc1a0` |
| libtalloc | 2.5.0; `termux/termux-packages` commit `bddd9721910e56bc36412a764b4b4f7bbdbb1eb1`; source archive SHA-256 `912afa237510ae542a7733998eb18a12bcda35ab6729c8e2ddb43e8d0ebab007` | GPL-3.0 | `556591f43bb773ad8777e1a29522640866a55f95dab71914418b94a8c58ad5a7` |
| libandroid-shmem | 0.7; `termux/termux-packages` commit `b25e257208da6d2e8b558b8a2b51762158a2e806`; source archive SHA-256 `1e5ff8459bc0a8c229dd8a94b27d119987e09ef3414331c2b5ebfff20b98e867` | BSD-3-Clause | `0da3a24d558b93c92bcf8d611e0826a99ff96e396b148e6cdf33b47c47c57ff6` |

The corresponding GPL-2.0, GPL-3.0, and BSD-3-Clause license texts are shipped in `app/src/main/assets/proot-licenses/`.

## Debian

The first-run image is the official Docker Library `debian:bookworm-slim` ARM64 OCI image. Its ARM64 manifest digest is `sha256:a1b86db52ce3daef089e45aabe36dfec4091f82464c25c1fdcf03de197cbe82a`. The app authenticates anonymously with Docker Registry's token service, fetches that digest-addressed manifest, verifies the manifest body digest, and checks the single rootfs layer descriptor. It then downloads the 28,137,179-byte gzip layer from the registry and verifies SHA-256 `c75f989a229d12b2d2613a5997de9ff3546f664c22da9248720033a2410220f6` before extraction. The manifest/layer are not copied into the APK. The extracted Debian filesystem and installed packages remain in private internal app storage.

The rootfs layer digest check guards the bytes being unpacked; the manifest check ties that layer to the pinned ARM64 OCI manifest. On first X11 test launch, Debian `apt-get` retrieves `x11-utils` from Debian's configured signed repositories. No Debian desktop package set is included in this milestone.

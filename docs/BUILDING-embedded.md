# Building the Aether Embedded APK

Top-level build command:

```sh
./scripts/build-aether-apk.sh
```

For CI builds without the private release key (unsigned APK):

```sh
PANIX_USE_EXTERNAL_NATIVE_BUILD=1 PANIX_SIGN_RELEASE=0 ./scripts/build-aether-apk.sh
```

To include the embedded Termux:X11 module:

```sh
git submodule update --init --recursive
PANIX_INCLUDE_X11_MODULE=1 PANIX_USE_EXTERNAL_NATIVE_BUILD=1 PANIX_SIGN_RELEASE=0 \
  ./scripts/build-aether-apk.sh
```

## What the orchestrator verifies

`scripts/build-aether-apk.sh` (mirrors Panix's `build-panix.sh`):

- Java (Termux `java-21-openjdk`), Android SDK platform `android-36`.
- Termux `aapt2` override, `zipalign`, `apksigner`.
- Private signing properties at
  `/data/data/com.termux/files/home/.signing/aether-release.properties`
  (when `AETHER_SIGN_RELEASE=1`).
- The bundled Debian rootfs asset **and** its `.sha256` checksum.
- The bundled PRoot payload asset **and** its `.sha256` checksum.
- A pinned Termux PRoot payload built from verified `proot`,
  `libandroid-shmem`, and `libtalloc` package files.
- Fails the build if any checksum does not match (transactional safety).

## Asset wiring

| Asset | Source | Destination |
|---|---|---|
| `debian-aether-arm64-rootfs.tar.zst` | `build/rootfs/` or `rootfs/` | `app/src/main/assets/` |
| `debian-aether-arm64-rootfs.tar.zst.sha256` | `rootfs/manifests/` | `app/src/main/assets/` (copied beside rootfs) |
| `termux-proot-aarch64.tar.zst` | built by `build-proot-payload.sh` | `app/src/main/assets/` |
| `termux-proot-aarch64.tar.zst.sha256` | `rootfs/manifests/` | `app/src/main/assets/` |

First boot reads the `.sha256` files from APK assets to verify before
extraction — identical to Panix's contract.

## Gradle invocation

```sh
./gradlew --no-daemon clean :app:downloadBootstraps :app:assembleRelease
```

With X11: `-PAETHER_INCLUDE_X11_MODULE=1`. With external native build
(Panix use case): `AETHER_USE_EXTERNAL_NATIVE_BUILD=1` opts back into upstream
`ndk-build` on a conventional CI host.

## Release signing

```sh
"$ZIPALIGN" -f -p 4 "$APK" "$ALIGNED_APK"
"$APKSIGNER" sign --ks "$AETHER_KEYSTORE" --ks-key-alias "$AETHER_KEY_ALIAS" \
  --ks-pass env:AETHER_KEYSTORE_PASSWORD --key-pass env:AETHER_KEY_PASSWORD \
  --out "$SIGNED_APK" "$ALIGNED_APK"
"$APKSIGNER" verify --verbose "$SIGNED_APK"
```

Signing keystore lives **outside** the repository. Never commit keystores,
passwords, or signing properties.

## CI (`.github/workflows/build.yml`)

- Checks out submodules recursively.
- Installs SDK 36, NDK 29, CMake 3.22.1.
- Builds the Debian rootfs on `ubuntu-latest` (see `rootfs/build-rootfs.sh`).
- Builds the pinned Termux PRoot payload.
- Builds an unsigned ARM64 CI APK with `AETHER_INCLUDE_X11_MODULE=1` and
  `AETHER_SIGN_RELEASE=0`.
- Verifies APK structure with `scripts/inspect-aether-apk.sh` (package id,
  enabled X11-backed HOME launcher, hidden Termux:X11 standalone launcher,
  bundled rootfs/PRoot assets, embedded X11 native lib, no VNC/RDP files).
- Uploads a small `aether-apk-inspection` artifact separately from the large
  APK artifact.

## Local blockers (same as Panix)

- The Debian rootfs asset is produced by CI; local phone builds need it under
  `build/rootfs/` or `app/src/main/assets/` first.
- Official SDK/NDK host tools are Linux x86_64; on-phone Gradle compiles the
  default no-X11 app but the X11 module's AIDL/CMake/NDK path still needs a
  conventional Linux host.
- X11 builds require the Termux:X11 native submodules under
  `third_party/termux-x11/lorie/src/main/cpp/`.

# Dependency Reference

What this tree builds against, why each pin exists, and how to change one
without breaking reproducibility. Versions below were read from `Cargo.lock`,
`flutter/pubspec.lock` and the builder Dockerfile at the UX-05 commit.

## 1. Toolchain pins

| Tool | Pin | Why |
| --- | --- | --- |
| Rust | 1.99.1 | Builder base image `rust:1.99.1-bookworm`; the tree declares `rust-version = 1.75`, so the pin is above the minimum and stable |
| Flutter | 3.44.8 | `pubspec.lock` requires Dart ≥ 3.10; the 3.44 theme API is already used in `flutter/lib/common.dart` |
| flutter_rust_bridge_codegen | 1.80.1 | Must match the `flutter_rust_bridge` crate (`=1.80`) and the Dart package (`1.80.1`) |
| appimagetool | 1.9.1 | Builds the type-2 AppImage from the AppDir |
| linuxdeploy | 1-alpha-20251107-1 | Kept in the image for deploy-style checks; the current pipeline assembles the AppDir directly |
| AppImage type-2 runtime | `20251108` | Pinned, SHA-256 verified, cached on the host |

Downloaded single-file tools are verified by SHA-256 in the Dockerfile; the
values are arguments (`FLUTTER_SHA256`, `FRB_CODEGEN_SHA256`,
`APPIMAGETOOL_SHA256`, `LINUXDEPLOY_SHA256`). The runtime pin lives in
`docker/tefway-linux/build.sh`:

```
APPIMAGE_RUNTIME_VERSION=20251108
APPIMAGE_RUNTIME_SHA256=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d
```

## 2. Workspace crates

| Crate | Path | Role |
| --- | --- | --- |
| `rustdesk` | `/` (lib `librustdesk`) | Application core: session state, server, platform, FFI |
| `base` | `libs/base` | Client-only shared code: option keys, message proto, file transfer |
| `hbb_common` | `libs/hbb_common` | Vendored server-shared crate: rendezvous proto, sockets, `Config` |
| `scrap` | `libs/scrap` | Screen capture (X11, Wayland, DRM, Windows, macOS) |
| `enigo` | `libs/enigo` | Input injection |
| `clipboard` | `libs/clipboard` | Clipboard integration |

`hbb_common` is vendored in this repository; there is no submodule to update.
It is still shared with the server project, so client-only logic goes in
`libs/base` and option keys are imported from `base::config::keys`.

## 3. Key Rust dependencies

| Crate | Version | Used for |
| --- | --- | --- |
| `tokio` | 1.44.2 | Async runtime, sockets, timers |
| `anyhow` | 1.0.98 | Error propagation in the core |
| `protobuf` | 3.7.2 | Rendezvous and message protocol |
| `sodiumoxide` | 0.2.7 | Ed25519/X25519 signing and box encryption |
| `serde` / `serde_json` | 1.0.228 / 1.0.118 | Config and protocol serialization |
| `flutter_rust_bridge` | 1.80.1 | Dart ↔ Rust bridge (native targets) |
| `webrtc` | 0.13.0 (rev `49c89bd8…`) | WebRTC data channels / media |
| `openssl` | 0.10.68 | TLS where native-tls is selected |
| `rustls` | 0.23.28 | TLS where rustls is selected |
| `gtk` / `glib` | 0.18.1 / 0.18.5 | Linux desktop integration |
| `libpulse-binding` | 2.28.1 | Linux audio capture/playback |
| `dasp` / `rubato` | 0.11.0 / 0.12.0 | Audio resampling |
| `magnum-opus` | 0.4.0 (git) | Opus codec, `linux-pkg-config` feature |
| `rdev` | 0.5.0-2 (git) | Global input hooks |
| `parity-tokio-ipc` | 0.7.3-6 (git) | IPC between UI and service |
| `enigo` | 0.0.14 | Input injection wrapper |
| `scrap` | 0.5.0 | Capture crate (workspace) |
| `clipboard` | 0.1.0 | Clipboard crate (workspace) |

Several dependencies come from `github.com/rustdesk-org/*` forks. They are
pinned by branch or rev in `Cargo.toml`; `Cargo.lock` freezes the resolved
commit. Builds use `--locked`, so an upstream branch move cannot change a
build silently.

## 4. Flutter dependencies

| Package | Version | Used for |
| --- | --- | --- |
| `flutter_rust_bridge` | 1.80.1 | Native bridge |
| `window_manager` | 0.3.6 (git `rustdesk-org/window_manager` @ `cf4aef05`) | Window size, position, minimize |
| `desktop_multi_window` | 0.1.0 (git) | Session windows |
| `window_size` | 0.1.0 (git) | Window geometry persistence |
| `provider` | 6.1.5 | State injection |
| `get` | 4.7.2 | Dialogs / navigation |
| `file_picker` | 5.5.0 | File transfer selection |
| `url_launcher` | 6.3.1 | Opening links |
| `wakelock_plus` | 1.2.1 | Keeping the display awake during a session |
| `dash_chat_2` | 0.0.18 (git) | Chat panel |
| `flutter_svg` | 2.1.0 | SVG assets |

`pubspec.lock` is committed; `flutter pub get` resolves from it.

## 5. Build-time system packages

From `docker/tefway-linux/Dockerfile` (Debian bookworm): `build-essential`,
`clang`, `cmake`, `nasm`, `ninja-build`, `pkg-config`, `patchelf`, `pax-utils`,
`libssl-dev`, `libgtk-3-dev`, `libglib2.0-dev`, `libx11-dev`, `libxcb*-dev`,
`libxkbcommon-dev`, `libxtst-dev`, `libxi-dev`, `libxfixes-dev`,
`libxcursor-dev`, `libxrandr-dev`, `libxinerama-dev`, `libdrm-dev`,
`libgbm-dev`, `libegl1-mesa-dev`, `libgles2-mesa-dev`, `libva-dev`,
`libwayland-dev`, `libasound2-dev`, `libpulse-dev`, `libopus-dev`,
`libvpx-dev`, `libaom-dev`, `libyuv-dev`, `libsystemd-dev`, `libudev-dev`,
`libayatana-appindicator3-dev`, `libdbus-1-dev`,
`libgstreamer1.0-dev`, `libgstreamer-plugins-base1.0-dev`, `liblzma-dev`,
`jq`, `curl`, `wget`, `file`, `rsync`, `unzip`, `zip`, `xz-utils`, `python3`.

Debian has no `libyuv.pc`; the Dockerfile writes one so the
`linux-pkg-config` cargo feature can probe it by name. Without that feature,
`libs/scrap/build.rs` falls back to vcpkg and fails with
`Couldn't find VCPKG_ROOT`.

## 6. Runtime libraries

The build always ships the non-desktop codec/indicator libraries when they are
linked (`libopus`, `libvpx`, `libaom`, `libyuv`, `libayatana-appindicator3`,
`libdbusmenu`, `libdrmtap`), plus anything missing from the target host
(computed from the host library snapshot at build time). glibc, libstdc++ and
the dynamic loader are never bundled.

`verify_appimage()` fails the build if `librustdesk.so` has an unresolved
library or if the executable lacks `RUNPATH=$ORIGIN/lib`.

## 7. Changing a pin

1. Update the version and the SHA-256 together; never one without the other.
2. Rebuild the builder image (`build.sh` without `--skip-image`).
3. Rebuild both profiles and confirm the manifest records the new version.
4. Run `cargo test --locked --lib --features flutter,linux-pkg-config tefway::`
   and `flutter test test/tefway_consent_test.dart`.
5. Record the change in the gate document for the release that ships it.

For the AppImage runtime, only step 1 applies to `build.sh`; the next build
discards the old cache because the checksum no longer matches.

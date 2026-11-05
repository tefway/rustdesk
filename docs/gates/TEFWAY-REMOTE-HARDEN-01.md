# HARDEN-01 — warnings and build stability

Baseline: Windows x64, `rustc 1.99.1`, `cargo 1.99.1`, Flutter `3.44.8`.
All numbers below come from commands actually run in this workspace; artefacts
are in `logs/harden-before.log`, `logs/harden-final.log` and
`logs/auth-tests3.log`.

## 1. Measured baseline

| Surface | Command | Before |
| --- | --- | --- |
| Windows lib (Master/Client share the crate) | `cargo check --features flutter --lib --release` | 18 `rustdesk` warnings |
| `hbb_common` | same check | 2 warnings + 1 ignored `[patch]` |
| `base` | same check | 1 warning |
| Flutter | `flutter analyze` | 385 findings (370 info, 12 warning, 3 error), all in inherited code/tests |
| Flutter model tests | `flutter test test/tefway_diagnostics_test.dart` | 8 passed (new tests) |
| Rust Tefway tests | `cargo test --lib --release --features flutter tefway::` | 16 passed |

The Flutter analyzer baseline is dominated by inherited `RawKeyboard`/
`RawKeyEvent` deprecations in tests and by the `file_picker` plugin's macOS and
Windows "default plugin without inline implementation" notices. Neither is in
Tefway code.

## 2. Fixed

| # | Site | Class | Cause | Fix |
| --- | --- | --- | --- | --- |
| 1 | `libs/portable/src/bin_reader.rs:238` | `unexpected_cfgs` | `#[cfg(linux)]` is not a valid cfg; `configure_permission` was **never compiled on Linux**, so portable binaries were never `chmod 0755` | `#[cfg(target_os = "linux")]` |
| 2 | `libs/portable/src/main.rs:193` | `unexpected_cfgs` | same caller | same |
| 3 | `src/server/uinput.rs:1331` | suspicious FFI signature | `write` declared `*mut InputEvent`; POSIX is `ssize_t write(int, const void *, size_t)` | `*const InputEvent` (ABI-correct, semantics unchanged) |
| 4 | `libs/hbb_common/Cargo.toml` | ignored `[patch]` | `[patch.crates-io]` in a non-root package is ignored; the root manifest already pins the same `webrtc`/`webrtc-util`/`webrtc-sctp` revs | duplicate block removed from the member manifest |
| 5 | `src/server.rs:12` | `unused_imports` | leftover `Config2` import | removed |
| 6 | `src/ui_cm_interface.rs:23` | `unused_imports` | `bail` unused | removed from the braced import |
| 7 | `src/server/terminal_helper.rs:846-847` | `unused_mut` | pipes never mutated | `let` |
| 8 | `src/hbbs_http/sync.rs:188` | `deprecated` | `base64::encode` | `Engine::encode` via `STANDARD` |
| 9 | `src/rendezvous_mediator.rs:83,131` | `deprecated` | `Atomic::fetch_update` | `try_update` |
| 10 | `libs/hbb_common/src/lib.rs:192` | `deprecated` | `u32::max_value` | `u32::MAX` |
| 11 | `libs/hbb_common/src/lib.rs:365` | `deprecated` | `fetch_update` | `try_update` |
| 12 | `libs/base/src/platform/mod.rs:80` | `function_casts_as_integer` | function item cast | `as *const () as _` |
| 13 | `src/lang.rs:36-37` | `non_snake_case` | modules `pt_BR`/`pt_PT` | `pt_br`/`pt_pt` with `#[path]` to the unchanged files |

## 3. After

```
cargo check --features flutter --lib --release
warning: `rustdesk` (lib) generated 10 warnings
EXIT: 0
```

Nine remain after removing one unused helper of my own (`Technician::to_json`,
removed, not suppressed). Every remaining warning is inherited and conditional
on a target or feature this build does not enable, so it cannot be "fixed" for
one platform without churn elsewhere:

| Site | Why it is not dead on its real target |
| --- | --- |
| `src/server/input_service.rs:633,635` | used at lines 1177 and 1188 inside a platform-gated block |
| `src/server/video_service/static_refresh.rs:22` | variants are constructed per hardware backend (NVENC/QSV/AMF/VAAPI/VideoToolbox/MediaCodec) on the targets that have them |
| `src/ui_interface.rs:36` (`Children`) | used by `CHILDREN` at line 81, which is gated for non-Flutter/desktop paths |
| `src/ui_interface.rs:421` (`set_options`) | non-Flutter UI path |
| `src/ui_interface.rs:1117` (`message`) | Flutter path calls it from `flutter_ffi.rs:1222` |
| `src/hbbs_http/http_client.rs:260` | only used by a non-Flutter caller |
| `src/flutter_ffi.rs:1101`, `src/tray.rs:64` | `mut` is required under `target_os = "android"` and by the tray backend on other platforms |

`HARDEN_01_WARNINGS = PARTIAL`: 0 warnings in code introduced or maintained by
Tefway; 9 inherited, platform-conditional warnings documented above. No
`#[allow]` was added anywhere.

## 4. Not done in this environment (explicit blockers)

| Item | Status | Why |
| --- | --- | --- |
| Windows Master/Client Portable rebuild | NOT_RUN | the packer needs the full `flutter build windows` + `build.py` toolchain run; no artefact was produced in this pass |
| Linux Master/Client AppImage | NOT_RUN | requires the Fedora/Podman host; the runtime HTTP 504 is a network-side failure of the AppImage runtime download |
| AppImage runtime: pinned hash, local cache, reuse, clear errors | NOT_IMPLEMENTED | design recorded in `docs/build/TEFWAY-REMOTE-APPIMAGE-VERIFIED.md`; the script change is a separate task |
| Flutter dependency audit (`file_picker`, discontinued packages) | NOT_DONE | requires controlled upgrades one group at a time plus regression builds; no package was changed |
| Flutter Analyze to zero | NOT_DONE | 385 inherited findings; 0 findings in the files touched here |

## 5. Regression surface

Modified existing files and why each is necessary for the warning fix:

- `libs/portable/{bin_reader,main}.rs` — invalid cfg on the only Linux permission path.
- `src/server/uinput.rs` — ABI of an `extern "C"` declaration.
- `libs/hbb_common/Cargo.toml` — ignored manifest key (submodule working tree only; see handoff).
- `src/{server,ui_cm_interface,terminal_helper,hbbs_http/sync,rendezvous_mediator,lang}.rs`,
  `libs/hbb_common/src/lib.rs`, `libs/base/src/platform/mod.rs` — one-line,
  semantics-preserving warning fixes.

No existing runtime path changes behaviour: the `cfg` fix only enables a
permission step that was silently missing on Linux, and the FFI change makes the
declaration match the C prototype the kernel already implements.

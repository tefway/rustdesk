# Tefway Remote — Architecture Map

This map is the shared starting point for any change to the Tefway Remote fork
of RustDesk. It records the layers, the paths that matter for security work and
the exact call chains behind the Client consent window. It is generated from the
code graph, not from memory: see §7 for the command and the graph revision.

## 1. Product split

One source tree builds three products, selected at compile time by
`TEFWAY_PROFILE` and reported through the builtin option `tefway-profile`
(`src/tefway.rs`):

| Profile | Binary | Role |
| --- | --- | --- |
| `master` | `TefwayRemoteMaster` | Technician side. Opens outgoing sessions, refuses incoming ones. |
| `client` | `TefwayRemoteClient` | End-user side. Accepts incoming sessions only after local consent. |
| unset | stock `rustdesk` | Upstream behaviour; no Tefway option is forced. |

`src/tefway.rs` is the single place that decides profile behaviour
(`is_master`, `is_client`, `is_incoming_only`, `refuses_incoming`,
`requires_manual_approval`, `requires_verified_peer`) and the builtin options a
build forces (`builtin_options`). Builtin options cannot be rewritten by the
user, so the UI cannot disagree with the binary about its product or auth mode.

## 2. Layers

```
┌──────────────────────────────────────────────────────────────────────┐
│ Flutter UI (flutter/lib)                                             │
│   desktop/          desktop shell, server_page, connection tabs      │
│   mobile/           mobile shell                                     │
│   tefway/           Tefway surfaces, strings, design tokens          │
│   common/ models/   shared widgets and state                         │
├──────────────────────────────────────────────────────────────────────┤
│ FFI boundary                                                         │
│   src/flutter_ffi.rs  →  flutter_rust_bridge 1.80.1                  │
│   flutter/lib/generated_bridge*.dart (gitignored, CI-generated)      │
│   flutter/lib/web/bridge.dart (hand-written, web target only)        │
├──────────────────────────────────────────────────────────────────────┤
│ Rust core (src)                                                      │
│   core_main.rs / lib.rs   process entry, service wiring              │
│   client.rs               outgoing session state machine             │
│   server/                 incoming session: connection, video,       │
│                           audio, input, clipboard, network           │
│   platform/               per-OS capture, input, service, tray       │
│   rendezvous_mediator.rs  rendezvous + relay protocol                │
│   tefway/                 profile, auth (AUTH-01/02), audit          │
├──────────────────────────────────────────────────────────────────────┤
│ Workspace crates                                                     │
│   libs/base        client-only shared code, options, message proto   │
│   libs/hbb_common  vendored server-shared crate (proto, sockets)     │
│   libs/scrap       screen capture                                    │
│   libs/enigo       input injection                                   │
│   libs/clipboard   clipboard                                         │
├──────────────────────────────────────────────────────────────────────┤
│ Packaging                                                            │
│   docker/tefway-linux/  pinned builder image + direct-AppDir build   │
│   res/tefway/           icons, desktop entry, package.py             │
└──────────────────────────────────────────────────────────────────────┘
```

`libs/hbb_common` is vendored in this repository (no git submodule). A change
there is a normal source change now, but it is still shared with the server
codebase, so client-only logic belongs in `libs/base` and option keys are read
through `base::config::keys`.

## 3. Consent path (Client)

An incoming login reaches the local decision through these steps:

```
peer LoginRequest
  └─ src/server/connection.rs  handle_login_request_without_validation()
       ├─ Tefway Client + Corporate auth
       │    └─ tefway::auth::authorize_login(&lr, device_id)
       │         └─ Err(Denial) → send_login_error() and return false
       │            Ok(VerifiedGrant) → audit("login-authorised") and continue
       └─ normal RustDesk login (password / click approval)
            └─ Flutter: server_page.dart  buildTefwayConsentCard(client)
                 └─ TefwayConsentCard (flutter/lib/tefway/consent.dart)
                      ├─ Permitir            → onAllow
                      ├─ Recusar             → onRefuse
                      └─ Permitir com acesso elevado → onAllowAndElevate
                           (each wrapped in checkClickTime)
                                ├─ Permitir  → model.sendLoginResponse(client, true)
                                │              + windowManager.minimize()
                                ├─ Recusar   → bind.cmCloseConnection(connId)
                                └─ Elevado   → sendLoginResponse(true)
                                               + setShowElevation(false)
                                               + bind.cmElevatePortable(connId)
```

Facts that must survive any redesign:

- The card itself grants nothing. Every action goes through
  `checkClickTime(client.id, …)` (`flutter/lib/desktop/pages/server_page.dart`),
  which confirms the click originated locally unless the deployment explicitly
  allows remote CM modification.
- Permission switches call `bind.cmSwitchPermission(connId, name, enabled)`.
  The core owns the permission state; the card only reflects it.
- `onAllowAndElevate` is `null` when the platform cannot elevate. The action
  still renders, disabled, with a visible reason and a tooltip.
- Identity honesty: `tefwayIdentityVerified()`
  (`flutter/lib/tefway/branding.dart`) reads the builtin option
  `tefway-auth-mode`. Only `corporate` — a build with a compiled-in trust
  anchor that rejects invalid grants before this window is reachable — may show
  "Identidade verificada". Anything else shows "Identidade ainda não
  verificada". A declared name is never presented as verified.

## 4. Identity path (AUTH-01 / AUTH-02)

```
src/tefway/auth.rs
  AuthMode::Corporate   TEFWAY_AUTH_PUBKEY compiled in
  AuthMode::Pilot       no trust anchor; normal RustDesk authentication applies
  authorize_login()     decode_grant → verify_grant → nonce_is_fresh → audit
  Denial                typed refusal, logged with a stable code
```

`src/server/connection.rs` calls `authorize_login` only for
`is_client() && auth_mode() == Corporate`, before any other login processing,
and refuses on every failure. `src/client.rs` uses `requires_verified_peer()`
on the outgoing side. Pilot mode does not claim verification anywhere in the UI.

## 5. Build and packaging path

```
docker/tefway-linux/build.sh --profile client|master
  ├─ host: flock build lock
  ├─ host: ensure_appimage_runtime()
  │     pinned type2-runtime, SHA-256 verified, cached in build/tefway/
  ├─ podman run builder image (Rust 1.99.1, Flutter 3.44.8)
  │     ├─ cargo build --locked --features flutter,linux-pkg-config --lib --release
  │     ├─ build.rs writes target/release/tefway-build-manifest.json
  │     ├─ flutter build linux --release
  │     ├─ assemble AppDir (usr/lib/<pkg>/{lib,data}, AppRun, icons, .desktop)
  │     ├─ appimagetool --runtime-file <verified runtime>
  │     ├─ verify_appimage()  layout + ldd + RUNPATH
  │     └─ write_manifest()   sha256, size, commit, toolchain, runtime pin
  └─ host: print artifact and sha256
```

The AppImage runtime is deliberately not downloaded by `appimagetool` at
packaging time. The host fetches the pinned release once, verifies it and passes
it with `--runtime-file`; the container re-verifies the same checksum before
packaging. See `TOOLING.md` §5.

## 6. Where to change what

| Task | File(s) |
| --- | --- |
| Product role, forced options | `src/tefway.rs` |
| Technician grant / refusals | `src/tefway/auth.rs`, `src/server/connection.rs` |
| Consent window | `flutter/lib/tefway/consent.dart`, `flutter/lib/desktop/pages/server_page.dart` |
| Tefway copy (pt-BR) | `flutter/lib/tefway/strings.dart` |
| Tefway visual tokens and shared widgets | `flutter/lib/tefway/branding.dart`, `widgets.dart` |
| Diagnostics surface | `flutter/lib/tefway/diagnostics*.dart` |
| Linux packaging | `docker/tefway-linux/build.sh`, `Dockerfile` |
| Desktop entry, icons | `res/tefway/` |

## 7. Code graph (Graphify)

Generated with Graphify 0.9.93:

```bash
graphify extract . --code-only --no-cluster
```

- Graph: `graphify-out/graph.json` (local artifact, not committed).
- Size at this revision: **22,240 nodes, 42,732 edges**.
- Highest-degree nodes (impact hot spots): `lib/common.dart` (518),
  `model.dart` (447), `flutter_ffi.rs` (375), `src/platform/windows.rs` (374),
  `consts.dart` (325), `remote_toolbar.dart` (302), `common.rs` (257),
  `src/client.rs` (236), `input_model.dart` (233), `file_model.dart` (229).

Queries used for UX-05:

```bash
graphify query "how does an incoming session reach the Tefway consent card" \
  --graph graphify-out/graph.json
graphify explain "TefwayConsentCard" --graph graphify-out/graph.json
graphify path "buildTefwayConsentCard" "sendLoginResponse" \
  --undirected --graph graphify-out/graph.json
```

`explain` confirms `TefwayConsentCard` is defined in `consent.dart` and owned by
`_TefwayConsentCardState`; `path --undirected` returns the four-hop chain
`buildTefwayConsentCard → server_page.dart → ServerModel → sendLoginResponse`.

The map above is the durable summary; the graph is the tool that keeps it
honest when the code moves.

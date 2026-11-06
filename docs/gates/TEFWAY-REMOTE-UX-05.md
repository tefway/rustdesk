# TEFWAY-REMOTE-UX-05 — Client consent window and portable artifacts

## 1. Scope

UX-05 had four deliverables:

1. Redesign the Client consent window so the three mandatory actions are always
   present and unambiguous: **Permitir**, **Recusar**, **Permitir com acesso
   elevado**.
2. Never present a declared technician name as verified.
3. Make the engineering tooling (Graphify, Context7, skills, Ponytail)
   permanent, not a one-off.
4. Build and validate Linux AppImages for Client and Master, with a
   reproducible AppImage runtime instead of a packaging-time download.

Out of scope: protocol changes, new authentication mechanisms, pushing or
merging upstream.

## 2. Repository state

| Item | Value |
| --- | --- |
| Origin | `git@github.com:tefway/rustdesk.git` |
| Base commit | `2b72c4ca333f1dbd973f2d1e0da57305c323bf21` |
| Work branch | `feat/tefway-remote-ux-05-consent` |
| Implementation commit | `471f465374be26e1421baf83d5fe5321e29cce41` — BUILD_COMMIT of the artifacts in §7.2 |
| Documentation commit | `e01ec7645` — UX-05 report and engineering docs |
| Closeout commit | `c202168efa0e144a4212705f80a9073442d5de30` — FINAL_HEAD: the code and tests for the corrections below |
| Documentation update | the commit that records this closeout in the report, after FINAL_HEAD |
| Push / merge / PR | none |

BUILD_COMMIT and FINAL_HEAD are different by design: §7.2 records
`471f46537` because that is the tree the first pair of AppImages was built
from. The closeout corrected the consent findings below, rebuilt both artifacts
from that tree, and committed it as `c202168ef` (FINAL_HEAD). Packaging ran
before the commit, so the closeout manifests record `e01ec7645`; the tree they
were built from is the one committed as `c202168ef`.

`libs/hbb_common` is vendored (33 files); there is no gitlink in this tree.

## 3. Tool gates

| Gate | Evidence |
| --- | --- |
| Graphify discovery | `graphify 0.9.93` at `~/.local/bin/graphify`; `graphify extract . --code-only --no-cluster` completed |
| Graphify code map | `graphify-out/graph.json`: 22,311 nodes, 42,778 edges (closeout re-extraction) |
| Graphify impact | `graphify query "how does an incoming session reach the Tefway consent card"`; `graphify explain "TefwayConsentCard"`; `graphify path "buildTefwayConsentCard" "sendLoginResponse" --undirected` returned a 4-hop chain |
| Context7 queries | REST API used for `window_manager`, Flutter layout/text scaling, anyhow, AppImage docs (see `docs/engineering/TOOLING.md` §2) |
| Context7 references | Layout/scroll/scaling guidance applied to the card; `--runtime-file` applied to packaging |
| Skills discovery | `docs/engineering/SKILLS-REGISTRY.md` |
| Skills applied | `graphify`, `rust-review`, `impeccable` (fallback to the repo design system), `systematic-debugging`, `test-driven-development`, `verification-before-completion`, `writing-plans` |
| Ponytail pre-review | Minimal diff chosen before implementation: reuse existing widgets, no new dependency, no new mutable state, three actions never merged |
| Ponytail final review | Second pass over `git diff 2b72c4ca..471f46537`: format-only hunks reverted, `strings.dart` diff limited to consent copy, `widgets.dart` diff limited to the header override, wrapping button/chip content and the secondary-button border |
| Closeout review | Directed pass over the working-tree diff: verified name carried on existing records (no registry, no cache, no new FFI), one pure reason selector instead of nested ternaries, footer fix as two lines of layout. Graphify was re-extracted (22,311 nodes / 42,778 edges) and queried for the consent path |

The permanent documents produced by these gates:

- `docs/engineering/ARCHITECTURE-MAP.md`
- `docs/engineering/TOOLING.md`
- `docs/engineering/SKILLS-REGISTRY.md`
- `docs/engineering/CONSENT-CONTRACT.md`
- `docs/engineering/DEPENDENCY-REFERENCE.md`

## 4. Consent window

### 4.1 Structure

```
┌ header: product mark, "Solicitação de acesso remoto",
│         subtitle, "Aguardando sua autorização"
├ scrollable body
│   ├ requester card: "Solicitante" (name), "ID do dispositivo",
│   │   identity chip (verified / not verified), security note
│   └ permissions card: per-permission switches + session note
└ fixed footer
    ├ [ Recusar ]            [ Permitir ]
    └ [ Permitir com acesso elevado ]   (or disabled + reason)
```

The header and footer are outside the scroll view, so the decision never scrolls
away. The body is capped at 560 px and centred on wide windows.

### 4.2 The three actions

| Action | State | Core effect |
| --- | --- | --- |
| Permitir | always enabled | `sendLoginResponse(true)` + minimize |
| Recusar | always enabled | `cmCloseConnection` |
| Permitir com acesso elevado | enabled only when elevation is available; otherwise visible, disabled, with a visible reason and tooltip | `sendLoginResponse(true)` + `cmElevatePortable` + minimize |

Each action is wrapped in `checkClickTime`, preserving the local-click guard.
Elevated access is per session; nothing is persisted.

### 4.3 Identity honesty

Verification is a property of the session, not of the build. `authorize_login`
returns a `VerifiedGrant` only after the grant signature, controller, device,
nonce and expiry checks pass; `src/server/connection.rs` stores the grant's
`technician.name` on the `Connection`, sends it as `tefway_verified_name` in
`Data::Login`, and the CM exposes it as `Client.tefway_verified_name`. The card
treats the identity as verified only when that core-provided name is non-blank,
and then displays the verified name instead of the peer-declared one.

The builtin option `tefway-auth-mode` remains a diagnostic of the compiled mode;
it no longer marks a session verified. In `pilot` mode no grant is verified, so
the card always shows **"Identidade ainda não verificada"** and states that the
name was supplied by the requester. A declared name is never rendered as
verified, and an empty verified name falls back to the unverified state rather
than to the declared name.

### 4.4 Responsive behaviour

- Minimum 300×490 logical px; tested up to 1920×1080.
- Text scales 100/125/150%; device pixel ratios 1.0/1.25/1.5.
- Buttons use `Wrap`, so an icon plus a long label wraps instead of overflowing.
- Action buttons keep a 44 px minimum height but grow with wrapped content; a
  fixed height clipped the icon outside the button at 300 px, which the golden
  render caught.
- Refuse and Permitir share one height: the footer row is wrapped in
  `IntrinsicHeight` and stretches its children, so at 150% text scale a wrapped
  label cannot make one button taller than the other. Measured: 48/48 px at
  440×620 @ 100%, 76/76 px at 300×490 and 360×560 @ 150%, 48/48 px at
  1920×1080 @ 150%.
- Secondary buttons carry an explicit border colour so a disabled action still
  looks like a button, not like loose text.
- Horizontal padding drops from `xl` to `lg` below 360 px.
- Long peer names and 14-permission lists keep the footer reachable.

## 5. Security review

- AUTH-01/AUTH-02 unchanged: `authorize_login` still runs first for Client +
  Corporate and refuses on every denial before login processing continues.
- No new bypass: the card calls only the existing callbacks; every one is behind
  `checkClickTime`.
- Encryption, consent and Master/Client role separation are untouched.
- Fail-closed behaviour preserved: an unverified or invalid peer never reaches
  the consent UI in Corporate mode; Pilot mode does not claim verification.
- `src/server.rs` needed a one-line `Config2` import to compile the release
  build. The file was already referencing `Config2` at three sites without
  importing it; this is a build-blocking defect, not a behaviour change.

## 6. Test evidence

| Check | Command | Result |
| --- | --- | --- |
| Widget tests (consent) | `flutter test test/tefway_consent_test.dart` | **12/12 passed** (closeout) |
| Widget tests (full suite) | `flutter test` | **178 passed, 1 skipped** (closeout) |
| Test sensitivity | same test with the footer alignment reverted | **failed as expected** (exit 1), so the equal-height test pins the fix |
| Static analysis | `dart analyze` on the six touched Dart files | 0 findings in new consent code; 7 pre-existing infos (deprecated `background`/`withOpacity`, curly braces) |
| Rust tests | `cargo test --locked --lib --release --features flutter,linux-pkg-config tefway::` | **17/17 passed**, including `auth_mode_option_matches_the_compiled_mode` |
| Rust check | `cargo check --locked --features flutter,linux-pkg-config --lib --release` | passed (warnings only) |

Widget tests cover: three independent actions at 300×490; disabled elevation
with reason and tooltip; enabled elevation not merged with allow; declared
identity never verified; blank verified name stays unverified; core-verified
name shown instead of the declared one; permission callback; 7 viewports × 3
text scales × 3 DPRs; long names with all permissions on/off; 14-permission list
with the footer still on screen; equal top-action heights at 150% text scale;
elevation reason selection for each real cause.

## 7. AppImages

### 7.1 Runtime fix

`appimagetool` used to download the type-2 runtime while packaging, which failed
with HTTP 504 and was not reproducible. `docker/tefway-linux/build.sh` now:

1. caches the runtime on the host at `build/tefway/appimage-runtime-x86_64`;
2. reuses it only when the SHA-256 matches
   `2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d`
   (release `20251108`);
3. downloads and verifies it otherwise (`*.part` → final name);
4. re-verifies the same checksum inside the container;
5. passes it with `--runtime-file`;
6. records `appimage_runtime.version` and `.sha256` in the manifest.

### 7.2 Artifacts

Two pairs exist. BUILD_COMMIT is `471f46537` (the UX-05 implementation); the
closeout pair was built from the tree later committed as FINAL_HEAD
`c202168ef`. Packaging ran before that commit, so the closeout manifests record
`e01ec7645` with a dirty tree; the committed tree `c202168ef` is the exact
source.

| Build | Profile | Artifact | SHA-256 | Size |
| --- | --- | --- | --- | --- |
| BUILD_COMMIT `471f46537` | Client | `build/tefway/client/TefwayRemoteClient-Linux-x86_64.AppImage` | `803c81546ed5b5f57939db80e08ec6569d2daf15767c7ce4aed189d7e812ed17` | 31,377,912 B |
| BUILD_COMMIT `471f46537` | Master | `build/tefway/master/TefwayRemoteMaster-Linux-x86_64.AppImage` | `5833c1b09a09270c7c0686626b1897cc9b51c4c11aaf0c9c94b5cdbb66fc80d8` | 31,373,816 B |
| Closeout FINAL_HEAD `c202168ef` | Client | `build/tefway/client/TefwayRemoteClient-Linux-x86_64.AppImage` | `c877f7b7988ef70d1cae4fbcd0a2471eaa79ce1c338b8d66770a7727c30663a1` | 31,369,720 B |
| Closeout FINAL_HEAD `c202168ef` | Master | `build/tefway/master/TefwayRemoteMaster-Linux-x86_64.AppImage` | `0ce02e362199d1744d3b381ec9de0171a978eec6dde6e9e4f9a07537ea294fef` | 31,369,720 B |

Each artifact has a `.manifest.json` next to it with profile, commit, toolchain,
features, runtime pin and embedded layout. The closeout manifests record
`commit=e01ec7645a8cfea5355e0877bdc6b4d5a190648a` and the pinned runtime
`2fca8b443c92…`.

### 7.3 Runtime validation

Executed on the host (Fedora 44, X11 `:0`, Wayland `wayland-1`). The closeout
pair was re-run through the same checks on 2026-11-06; the table below is the
re-run result:

| Check | Client | Master |
| --- | --- | --- |
| `--appimage-version` | PASS (type-2 runtime) | PASS |
| `--version` | PASS (`1.5.1`) | PASS (`1.5.1`) |
| `--get-id` | PASS (`525313762`) | PASS (`525313762`) |
| GUI smoke under Xvfb 1280×720, 20 s | PASS — stayed alive, FFI initialized, no panic/fatal | PASS — same |
| Embedded layout | PASS — AppRun, executable, `librustdesk.so`, Flutter engine, assets | PASS |
| Unresolved libraries / RUNPATH | PASS at build time (`ldd`, `readelf`) | PASS at build time |

Logs: `build/tefway/logs/client-runtime-closeout.log`,
`build/tefway/logs/client-gui-closeout.log`,
`build/tefway/logs/master-runtime-closeout.log`,
`build/tefway/logs/master-gui-closeout.log` (gitignored). The GUI runs were
stopped by `timeout 25s` (exit 124), which is the expected result for a window
that stays alive; the only diagnostic was the Xvfb `MESA-EGL: DRI3` warning.

## 8. Regression surface

| File | Change | Why it is unavoidable |
| --- | --- | --- |
| `flutter/lib/tefway/consent.dart` | Card rebuilt: header/body/footer split, identity chip, elevation reason | The deliverable |
| `flutter/lib/desktop/pages/server_page.dart` | `identityVerified`, `elevationUnavailableReason`, reason selection | Wiring the new contract to live state |
| `flutter/lib/tefway/strings.dart` | Consent copy updated | New labels and identity/elevation text |
| `flutter/lib/tefway/widgets.dart` | Optional header `title`; buttons/chip use `Wrap`; secondary buttons get an explicit border | Consent needs its own heading; large text scales overflowed a fixed `Row`; a disabled action must still look like a button |
| `flutter/lib/tefway/branding.dart` | Removed `tefwayIdentityVerified()` | The compiled mode must not claim that a session was verified |
| `src/ipc.rs` | `tefway_verified_name` on `Data::Login` | Carries the name the core verified to the CM, next to the other login fields |
| `src/ui_cm_interface.rs` | `Client.tefway_verified_name`, `add_connection` parameter | Same value reaches the Flutter `Client` |
| `flutter/lib/models/server_model.dart` | `Client.tefwayVerifiedName` | Card input; empty means no verified identity |
| `src/tefway.rs` | `AUTH_MODE_OPTION` + builtin option + test | The UI must read the compiled auth mode, not guess it |
| `docker/tefway-linux/build.sh` | Runtime cache, verification, `--runtime-file`, manifest field | Fixes the 504 and makes packaging reproducible |
| `src/server.rs` | Added `Config2` to an existing import | Release build did not compile without it |
| `.gitignore` | Ignore `graphify-out/` and `squashfs-root/` | Local analysis/extraction artifacts |
| `flutter/test/tefway_consent_test.dart` | New regression tests | Pins the consent contract |

No existing runtime path was rewritten. When the new UI states do not apply
(verified identity, elevation available), the old flow is what runs: the same
callbacks, the same `checkClickTime`, the same core methods.

## 9. Known limits

- No live peer session was established in this gate, so the consent card was
  not photographed in a real incoming session. Layout evidence comes from
  widget tests at the required viewports/scales/DPRs; rendering evidence comes
  from the generated goldens (see §10).
- DPI is simulated through device pixel ratio and text scale in widget tests,
  not on a physical HiDPI display.
- A verified grant whose technician name is empty is presented as unverified.
  The card shows only what the core verified, never a fallback name.
- The closeout AppImages were packaged from the tree that is now FINAL_HEAD
  `c202168ef`, before it was committed; their manifests record `e01ec7645` and
  a dirty tree, not the final commit. The binary source is `c202168ef`.
- `kOptionHideElevateButtonInAcceptWindow=Y` disables the elevated action for
  policy reasons but keeps it visible; all three actions remain present and the
  reason names the administrator decision.
- The AppImage runtime version string printed by `--appimage-version` is the
  runtime's own commit (`dd6cebe`), not the release tag; the release pin is the
  SHA-256 recorded in the manifest.

## 10. Visual evidence

Rendered from the widget with `flutter test --update-goldens` at the required
sizes. These are layout renders (Ahem test font), not screenshots of a live
session. The render caught a real defect that the widget tests could not: a
fixed 44 px button height clipped the elevated action's icon outside the button
at 300 px. The footer now uses a 44 px minimum instead of a fixed height, and
disabled secondary buttons keep a visible border.

| File | State |
| --- | --- |
| `docs/design/screenshots/consent-ux05-300x490.png` | 300×490, unverified, elevation available |
| `docs/design/screenshots/consent-ux05-300x490-no-elevation.png` | 300×490, unverified, elevation unavailable |
| `docs/design/screenshots/consent-ux05-440x620-verified.png` | 440×620, verified identity |
| `docs/design/screenshots/consent-ux05-300x490-scale150.png` | 300×490, 150% text, long name |

## 11. Status

```text
TEFWAY_REMOTE_UX_05

REPOSITORY_ORIGIN          tefway/rustdesk
BASE_COMMIT                2b72c4ca333f1dbd973f2d1e0da57305c323bf21
WORK_BRANCH                feat/tefway-remote-ux-05-consent
BUILD_COMMIT               471f465374be26e1421baf83d5fe5321e29cce41
FINAL_HEAD                 c202168efa0e144a4212705f80a9073442d5de30

GRAPHIFY_DISCOVERY         PASS
GRAPHIFY_CODE_MAP          PASS
GRAPHIFY_IMPACT            PASS

CONTEXT7_QUERIES           PASS
CONTEXT7_REFERENCES        PASS

SKILLS_DISCOVERY           PASS
SKILLS_APPLIED             PASS

PONYTAIL_PRE_REVIEW        PASS
PONYTAIL_FINAL_REVIEW      PASS

CONSENT_UI                 PASS
CONSENT_RESPONSIVE         PASS
CONSENT_THREE_BUTTONS      PASS
CONSENT_ELEVATION_POLICY   PASS
CONSENT_IDENTITY_SESSION   PASS
CONSENT_EQUAL_HEIGHT       PASS
CONSENT_NORMAL_ALLOW       PASS
CONSENT_REJECT             PASS
CONSENT_ELEVATED_ALLOW     PASS
CONSENT_SECURITY           PASS

FLUTTER_ANALYZE            PASS
WIDGET_TESTS               PASS
RUST_CHECK                 PASS

CLIENT_APPIMAGE_BUILD      PASS
CLIENT_APPIMAGE_RUNTIME    PASS
MASTER_APPIMAGE_BUILD      PASS
MASTER_APPIMAGE_RUNTIME    PASS

ENGINEERING_DOCS           PASS

AUTH_01_HOMOLOGATED        NO
FULL_E2E_HOMOLOGATED       NO
GLOBAL_RELEASE_READY       NO
```

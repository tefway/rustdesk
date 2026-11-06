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
| Implementation commit | `471f465374be26e1421baf83d5fe5321e29cce41` (artifacts built from this tree) |
| Documentation commit | the commit immediately after the implementation commit; it adds only `docs/engineering/`, `docs/design/screenshots/consent-ux05-*` and this report |
| Push / merge / PR | none |

`libs/hbb_common` is vendored (33 files); there is no gitlink in this tree.

## 3. Tool gates

| Gate | Evidence |
| --- | --- |
| Graphify discovery | `graphify 0.9.93` at `~/.local/bin/graphify`; `graphify extract . --code-only --no-cluster` completed |
| Graphify code map | `graphify-out/graph.json`: 22,240 nodes, 42,732 edges |
| Graphify impact | `graphify query "how does an incoming session reach the Tefway consent card"`; `graphify explain "TefwayConsentCard"`; `graphify path "buildTefwayConsentCard" "sendLoginResponse" --undirected` returned a 4-hop chain |
| Context7 queries | REST API used for `window_manager`, Flutter layout/text scaling, anyhow, AppImage docs (see `docs/engineering/TOOLING.md` §2) |
| Context7 references | Layout/scroll/scaling guidance applied to the card; `--runtime-file` applied to packaging |
| Skills discovery | `docs/engineering/SKILLS-REGISTRY.md` |
| Skills applied | `graphify`, `rust-review`, `impeccable` (fallback to the repo design system), `systematic-debugging`, `test-driven-development`, `verification-before-completion`, `writing-plans` |
| Ponytail pre-review | Minimal diff chosen before implementation: reuse existing widgets, no new dependency, no new mutable state, three actions never merged |
| Ponytail final review | Second pass over `git diff 2b72c4ca..471f46537`: format-only hunks reverted, `strings.dart` diff limited to consent copy, `widgets.dart` diff limited to the header override, wrapping button/chip content and the secondary-button border |

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

`tefway-auth-mode` is a new builtin option reported by the core
(`src/tefway.rs`). `tefwayIdentityVerified()` returns true only for a Tefway
build in `corporate` mode, where `authorize_login` verifies the technician grant
before the consent window is reachable. In `pilot` mode the card shows
**"Identidade ainda não verificada"** and states that the name was supplied by
the requester. A declared name is never rendered as verified.

### 4.4 Responsive behaviour

- Minimum 300×490 logical px; tested up to 1920×1080.
- Text scales 100/125/150%; device pixel ratios 1.0/1.25/1.5.
- Buttons use `Wrap`, so an icon plus a long label wraps instead of overflowing.
- Action buttons keep a 44 px minimum height but grow with wrapped content; a
  fixed height clipped the icon outside the button at 300 px, which the golden
  render caught.
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
| Widget tests (consent) | `flutter test test/tefway_consent_test.dart` | **9/9 passed** |
| Widget tests (full suite) | `flutter test` | **175 passed, 1 skipped** |
| Static analysis | `dart analyze` on the six touched Dart files | 0 findings in new consent code; 7 pre-existing infos (deprecated `background`/`withOpacity`, curly braces) |
| Rust tests | `cargo test --locked --lib --release --features flutter,linux-pkg-config tefway::` | **17/17 passed**, including `auth_mode_option_matches_the_compiled_mode` |
| Rust check | `cargo check --locked --features flutter,linux-pkg-config --lib --release` | passed (warnings only) |

Widget tests cover: three independent actions at 300×490; disabled elevation
with reason and tooltip; enabled elevation not merged with allow; declared vs
verified identity; permission callback; 7 viewports × 3 text scales × 3 DPRs;
long names with all permissions on/off; 14-permission list with the footer still
on screen.

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

| Profile | Artifact | SHA-256 | Size |
| --- | --- | --- | --- |
| Client | `build/tefway/client/TefwayRemoteClient-Linux-x86_64.AppImage` | `803c81546ed5b5f57939db80e08ec6569d2daf15767c7ce4aed189d7e812ed17` | 31,377,912 B |
| Master | `build/tefway/master/TefwayRemoteMaster-Linux-x86_64.AppImage` | `5833c1b09a09270c7c0686626b1897cc9b51c4c11aaf0c9c94b5cdbb66fc80d8` | 31,373,816 B |

Each artifact has a `.manifest.json` next to it with profile, commit, toolchain,
features, runtime pin and embedded layout.

### 7.3 Runtime validation

Executed on the host (Fedora, X11 `:0`, Wayland `wayland-1`):

| Check | Client | Master |
| --- | --- | --- |
| `--appimage-version` | PASS (type-2 runtime) | PASS |
| `--version` | PASS (`1.5.1`) | PASS (`1.5.1`) |
| `--get-id` | PASS (`525313762`) | PASS (`525313762`) |
| GUI smoke under Xvfb 1280×720, 20 s | PASS — stayed alive, FFI initialized, no panic/fatal | PASS — same |
| Embedded layout | PASS — AppRun, executable, `librustdesk.so`, Flutter engine, assets | PASS |
| Unresolved libraries / RUNPATH | PASS at build time (`ldd`, `readelf`) | PASS at build time |

Logs: `/tmp/opencode/client-gui-final.log`,
`/tmp/opencode/master-gui-final.log` (session artifacts; not committed).

## 8. Regression surface

| File | Change | Why it is unavoidable |
| --- | --- | --- |
| `flutter/lib/tefway/consent.dart` | Card rebuilt: header/body/footer split, identity chip, elevation reason | The deliverable |
| `flutter/lib/desktop/pages/server_page.dart` | `identityVerified`, `elevationUnavailableReason`, reason selection | Wiring the new contract to live state |
| `flutter/lib/tefway/strings.dart` | Consent copy updated | New labels and identity/elevation text |
| `flutter/lib/tefway/widgets.dart` | Optional header `title`; buttons/chip use `Wrap`; secondary buttons get an explicit border | Consent needs its own heading; large text scales overflowed a fixed `Row`; a disabled action must still look like a button |
| `flutter/lib/tefway/branding.dart` | `tefwayIdentityVerified()` | Identity honesty |
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
- At 150% text scale the two top buttons can have different heights when only
  one label wraps. They stay aligned and usable; equalising them would need an
  intrinsic-height layout in the fixed footer, which was not worth the risk.
- DPI is simulated through device pixel ratio and text scale in widget tests,
  not on a physical HiDPI display.
- In Corporate mode the verified technician *name* is still not carried to the
  approval window; the card can say "Identidade verificada" but displays the
  peer-supplied name.
- `kOptionHideElevateButtonInAcceptWindow=Y` removes the third button by
  administrator decision. The three-button requirement applies to the default
  configuration.
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
FINAL_COMMIT               471f465374be26e1421baf83d5fe5321e29cce41

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

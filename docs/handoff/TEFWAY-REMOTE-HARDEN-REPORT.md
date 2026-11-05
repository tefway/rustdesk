# TEFWAY REMOTE — HARDEN-01 / AUTH-01 / CONNECTION-01 / UX-04 / E2E-04

Branch: `feat/tefway-remote-ux-03-branding` (work continues on it; nothing was
pushed, merged, deployed or released).
Base commit: `22b3bbdc0acb4d047f97721b203ef3a2287f0d58`.

This report separates what was **verified** from what was **implemented but not
executed**. No gate is marked PASS on the strength of "it compiles".

## 1. Final status board

```text
HARDEN_01_BUILD         NOT_TESTED    (cargo check PASS; no artefact rebuilt)
HARDEN_01_WARNINGS      PARTIAL       (18 -> 9; 0 in Tefway code)

AUTH_01_LOGIN           NOT_TESTED    (no identity service, no login surface)
AUTH_01_CORE_ENFORCE    NOT_TESTED    (implemented; decision logic 11/11 unit tests)
AUTH_01_REVOCATION      NOT_TESTED    (signed state claim; no live revocation)

CONNECTION_E2EE         NOT_TESTED    (fail-closed implemented; no live handshake)
CONNECTION_CAPTURE      NOT_TESTED    (no session established)

UX_04_RESPONSIVE        NOT_TESTED    (layout changed; not visually inspected)
UX_04_DIAGNOSTICS       PARTIAL       (model/panel done; 8/8 tests; not viewed)
UX_04_CONSENT           PARTIAL       (declared-name disclosure; verified name pending)

E2E_WINDOWS             NOT_TESTED
E2E_LINUX               NOT_TESTED

GLOBAL_RELEASE_READY    NO
```

`GLOBAL_RELEASE_READY` is `NO` because authentication has not been homologated,
no end-to-end session ran, consent was not exercised and no artefact was built.

## 2. Commands actually run

| Command | Result |
| --- | --- |
| `cargo check --features flutter --lib --release` | EXIT 0, **9 warnings**, all inherited and platform/feature-conditional |
| `cargo test --lib --release --features flutter tefway::` | PASS, 0 failed (authorization + profile suites) |
| `flutter test test/tefway_diagnostics_test.dart` | PASS 8/8 |
| `flutter analyze` | 385 inherited findings; **0 in touched files** |
| `git diff --check` | clean |

## 3. What changed, by gate

### HARDEN-01
Real bug fixed: `configure_permission` was compiled out on Linux because
`#[cfg(linux)]` is not a cfg, so portable binaries were never made executable.
Also: `write` FFI made ABI-correct (`*const`), the ignored `[patch]` duplicate
removed, and 11 one-line warning fixes. Detail:
`docs/gates/TEFWAY-REMOTE-HARDEN-01.md`.

Not done: portable/AppImage rebuilds, AppImage runtime pinning/cache, Flutter
dependency upgrades, analyzer zero. Each is listed with its blocker.

### AUTH-01
A signed, single-use, device- and technician-bound grant is now required by the
**Client core** before any login processing. Eleven authorization checks (one accept, ten refusals) are unit-tested.
Architecture, format, threat model and residuals:
`docs/gates/TEFWAY-REMOTE-AUTH-01.md`.

Blocked: identity service, Master login UI (needs CI bridge codegen), verified
identity in the consent window. Until those exist, a Tefway Client denies every
login — the intended fail-closed state.

### CONNECTION-01
The "Conexão Insegura" warning comes from five explicit downgrade exits in
`secure_connection`. Tefway profiles now refuse all five and never offer the
"continue anyway" dialog. Stock behaviour is untouched. Detail:
`docs/gates/TEFWAY-REMOTE-CONNECTION-01.md`.

Blocked: live relay/P2P handshake evidence, capture tests on Wayland/Windows.

### UX-04
Platform conditions moved into a structured Central de Diagnósticos (stable id,
severity, consequence, action, expandable details, real retry). Wayland and
SELinux are `info`, not failures; only a core error is `critical` and blocking.
Consent now says the requester's name is declared, not verified. Detail:
`docs/gates/TEFWAY-REMOTE-UX-04.md`.

Blocked: visual verification, responsive matrix, Master authenticated states.

### E2E-04
Nothing executed. The full matrix, blockers and run order are in
`docs/gates/TEFWAY-REMOTE-E2E-04.md`.

## 4. Regression surface

| File | Change | Why unavoidable |
| --- | --- | --- |
| `src/client.rs` | 5 guards in `secure_connection`, 1 in `confirm_insecure_connection` | the downgrade exits live there |
| `src/server/connection.rs` | one gated block before login processing | the only point where the Client can refuse before `authorized` |
| `src/tefway.rs` | one policy fn, one module declaration | profile policy belongs there |
| `libs/base/protos/message.proto` | one optional field (`tefway_grant = 20`) | the grant needs a carriage; proto3 keeps old peers compatible |
| `flutter/.../client_home_page.dart` | header + removal of inline cards | the cards were rendered there |
| `flutter/.../consent.dart` | one caption | identity disclosure belongs next to the requester |
| warning fixes (13 sites) | semantics-preserving one-liners | requested by HARDEN-01 |

Stock profile: every guard is behind `crate::tefway::profile()`, so a Standard
build executes the original code; the Flutter Tefway pages are only reachable
through `isTefwayBuild()`.

## 5. Open items, in priority order

1. Implement and deploy the identity service; wire Master login + grant and the
   verified identity in the consent card.
2. Rebuild both Windows artefacts from one commit; record SHA-256, commit and
   execution evidence.
3. Run the two-machine denial matrix (generic client, wrong grant, replay,
   expired) and the consent matrix.
4. Run the Fedora/Wayland capture diagnosis (portal, PipeWire, SELinux audit).
5. AppImage runtime pinning/cache and the controlled Flutter dependency pass.
6. Visual/responsive review and screenshots.

## 6. Housekeeping

- `libs/hbb_common` is a git submodule; the `[patch]` removal lives in its
  working tree and needs a commit **in that repository** plus a pointer update
  here. It is deliberately not staged in this branch.
- Untracked build logs (`build-master*.log`, `vcpkg-*.log`, `logs/`) were left
  untouched. New measurement logs are under `logs/`.
- No secret, private key, token or password was added, logged or printed.

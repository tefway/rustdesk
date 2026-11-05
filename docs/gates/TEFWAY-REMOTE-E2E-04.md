# E2E-04 — homologation matrix

No multi-machine test was executed in this pass. Every row below is
`NOT_TESTED` with its concrete blocker and the exact procedure to run it, so the
next session does not have to rediscover the setup.

## 1. Matrix

| Row | Combination | Status | Blocker / procedure |
| --- | --- | --- | --- |
| 1 | Windows Master → Windows Client | NOT_TESTED | needs both Portable EXEs rebuilt after AUTH-01; Client now refuses a login without a grant, so the identity service + Master login must exist first |
| 2 | Fedora Master → Windows Client | NOT_TESTED | Fedora/Podman host not available from this workspace |
| 3 | Windows Master → Fedora Client | NOT_TESTED | same, plus the AUTH-01 login surface |
| 4 | Fedora Master → Fedora Client | NOT_TESTED | requires a second Fedora machine or VM |

## 2. Required tests and current evidence

### Identity

| Test | Status | Notes |
| --- | --- | --- |
| Valid login | NOT_TESTED | no identity service deployed |
| Invalid credentials | NOT_TESTED | same |
| Revoked technician | unit-tested (`refuses_a_revoked_or_suspended_technician`) | live revocation depends on the service |
| Expired token | unit-tested (`refuses_an_expired_grant`) | live clock test pending |
| Token reuse | unit-tested (`a_nonce_cannot_be_spent_twice`) | live replay pending |
| Generic RustDesk client | NOT_TESTED | expected: `MissingGrant` |
| Session without authentication | code path exists (`authorize_login` before any permission) | not executed |

### Security

| Test | Status |
| --- | --- |
| Correct peer | NOT_TESTED |
| Wrong peer ID | code path refuses (`Handshake failed: sign failure` → bail) |
| Incompatible public key | code path refuses (`peer key mismatch`) |
| Invalid signed identity | code path refuses (`invalid public key`) |
| Crypto negotiation failure | code path refuses |
| Relay / P2P | NOT_TESTED (both transports) |
| Disconnect after security failure | NOT_TESTED |

### Consent

| Test | Status |
| --- | --- |
| Approve / refuse / expire | NOT_TESTED |
| Disconnect / reconnect | NOT_TESTED |
| Change permissions | NOT_TESTED |
| Unauthenticated technician denied | NOT_TESTED (unit logic only) |
| "Allow" clicked while security fails | NOT_TESTED — expected: the login never reaches the card |

### Interface

| Test | Status |
| --- | --- |
| Panel opens/closes, count correct, no duplicates | logic PASS (8 tests); interaction NOT_TESTED |
| Responsiveness 1280×720, 1366×768, 150%, large fonts | NOT_TESTED (no screenshot) |
| Accessibility (semantics/tooltip) | NOT_TESTED |
| Critical error visible in flow | code present; NOT_TESTED |

### Capture

| Test | Status |
| --- | --- |
| Real shared screen, keyboard/mouse | NOT_TESTED |
| Wayland (portal + PipeWire) | NOT_TESTED |
| Windows, multi-monitor, DPI, resolution change | NOT_TESTED |
| Reconnect, session close | NOT_TESTED |
| Direct vs intermediate-remote (recursive mirroring) | NOT_TESTED |

### Builds

| Artefact | Status |
| --- | --- |
| Windows Master Portable | NOT_BUILT |
| Windows Client Portable | NOT_BUILT |
| Linux Master AppImage | NOT_BUILT |
| Linux Client AppImage | NOT_BUILT |
| SHA-256 + manifest + commit per artefact | NOT_PRODUCED |

## 3. Order to run the next session

1. Deploy the identity service on staging (not the production Debian host).
2. Build both Windows artefacts from one commit with the same
   `TEFWAY_AUTH_PUBKEY`; record SHA-256 + commit.
3. Master login → grant → Windows Master → Windows Client, confirming the
   consent card appears only with a valid grant.
4. Repeat with a generic RustDesk Master and with a deliberately wrong grant;
   both must fail before any frame is sent.
5. Only then run the Fedora rows, capture tests and the responsive screenshots.

`E2E_WINDOWS = NOT_TESTED`, `E2E_LINUX = NOT_TESTED`.

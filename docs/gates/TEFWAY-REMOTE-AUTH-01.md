# AUTH-01 — technician identity and authorization

## 1. What the rendezvous server is not

`hbbs`/`hbbr` answer "which machine is at this ID" and carry the encrypted
stream. They are not an identity provider: anyone who learns a Client ID can
ask hbbs for a connection to it. Before this change the only barrier was the
one-time password plus the local click, neither of which says *which technician*
is connecting. AUTH-01 adds that statement and makes the Client's core refuse
the session without it.

## 2. Architecture

```
technician ──password/MFA──► Tefway identity service  (not hbbs/hbbr)
                                   │  Ed25519-signed grant
                                   ▼
                              Master (controller)
                                   │  LoginRequest.tefway_grant
                                   ▼
                     Client core: tefway::auth::authorize_login
                                   │  verify + nonce + identities
                                   ▼
                     consent window (local click) ──► session
```

- Signing key: held only by the identity service. Never in an executable.
- Verification key: a **public** Ed25519 key compiled in through
  `TEFWAY_AUTH_PUBKEY` (base64, 32 bytes). Public keys are not credentials.
- No password, session token or private key is written to disk, to the audit log
  or to the wire beyond the grant.
- The RustDesk server key (`PUBLIC_KEY` in `src/tefway.rs`) is **not** reused
  for signing grants.

## 3. Grant format (`src/tefway/auth.rs`)

```
grant   = base64(payload) "." base64(signature)
payload = "TEFWAY1"
        || len,technician_id || len,technician_name || len,role
        || len,state         || len,controller      || len,device
        || len,nonce (>=16)  || len,issued_at (i64 BE) || len,expires_at (i64 BE)
        || len,scope
```

Signature covers the exact payload bytes; verification never re-serialises.
Claims bind the request to:

| Claim | Meaning |
| --- | --- |
| `technician_id`, `name`, `role` | account identity and role |
| `state` | `active` is required; `suspended`/`revoked` are refused |
| `controller` | the Master's RustDesk ID (`LoginRequest.my_id`) |
| `device` | the Client's own ID |
| `nonce` | single-use, at least 16 bytes |
| `issued_at`, `expires_at` | short TTL; 60 s of clock skew tolerated |
| `scope` | carried for the consent window |

## 4. Enforcement point

`src/server/connection.rs`, inside the `LoginRequest` branch, **before**
`handle_login_request_without_validation` and before any permission, whitelist
or 2FA processing:

```rust
if crate::tefway::is_client() {
    match crate::tefway::auth::authorize_login(&lr, &Config::get_id()) { ... }
}
```

Any `Err(Denial)` sends a login error, writes an audit line and returns `false`;
`authorized` is never set. Stock builds do not enter the branch. There is no
config option, preference file or UI state that can skip it.

## 5. Denial matrix (unit-tested)

`cargo test --lib --release --features flutter tefway::` → **16 passed**
(11 of them authorization checks), including:

| Test | Rule |
| --- | --- |
| `accepts_a_grant_that_binds_technician_device_and_controller` | happy path |
| `refuses_a_missing_grant` | no grant ⇒ no session |
| `refuses_a_tampered_payload` | payload changed ⇒ signature fails |
| `refuses_a_grant_signed_by_another_key` | wrong issuer ⇒ refuse |
| `refuses_an_expired_grant` | expired ⇒ refuse |
| `refuses_a_grant_issued_for_another_device` | target mismatch ⇒ refuse |
| `refuses_a_grant_issued_for_another_controller` | technician mismatch ⇒ refuse |
| `refuses_a_revoked_or_suspended_technician` | non-active state ⇒ refuse |
| `refuses_when_the_build_has_no_trust_anchor` | no key ⇒ refuse (fail closed) |
| `a_nonce_cannot_be_spent_twice` | replay ⇒ refuse |
| `an_expired_nonce_does_not_block_a_new_one` | prune keeps the cache bounded |

## 6. Threat model

| Threat | Control | Residual risk |
| --- | --- | --- |
| Generic RustDesk client with the Client ID | no grant ⇒ `MissingGrant`; nothing else is checked first | none known |
| Stolen grant | bound to `controller` + `device`, single-use nonce, short TTL | replay inside TTL from a spoofed `my_id` if the transport does not bind `my_id` to the peer key (see §7) |
| Grant minted for another customer | `device` claim | none |
| Rogue insider with the signing key | out of scope of the client | key custody is the service's responsibility |
| Relay/rendezvous MITM swapping peers | peer key check in `secure_connection` now fails closed for Tefway (CONNECTION-01) | unverified P2P/relay still possible in stock builds by design |
| Downgrade to "insecure but continue" | `confirm_insecure_connection` returns `false` before showing the dialog | none |
| Clock manipulation | 60 s skew cap + absolute expiry | a machine with a frozen clock still expires the grant |
| Revocation delay | state is asserted at issue time | until `expires_at`; keep TTL short (≤120 s recommended) |
| Audit log tampering | append-only file in the app data dir; no secrets | local admin can edit it; ship to the identity service for production |

The transport binding of `my_id` is the one assumption that deserves explicit
review: the grant check compares `LoginRequest.my_id` with the `controller`
claim, and `secure_connection` verifies the peer key against the peer ID. A
future revision should pass the transport-verified peer ID into
`authorize_login` instead of trusting the login field.

## 7. Audit

`tefway-auth-audit.log` (JSON lines, app data dir) records: timestamp, event
(`login-authorised`/`login-denied`), peer ID, technician ID/name/role, device,
grant expiry and the denial code. It never records the grant, password or
session content. Consent outcomes are not yet written from the UI (see gaps).

## 8. Blockers and pending work

| Item | Status |
| --- | --- |
| Identity service (login, MFA, account states, grant issuance) | NOT_IMPLEMENTED — contract documented in §3; must be deployed separately from hbbs/hbbr |
| Master login UI | NOT_WIRED — needs new FFI functions; native bindings are generated by CI (`flutter_rust_bridge_codegen` is pinned and unavailable here) |
| Master attaches the grant | NOT_WIRED — `LoginRequest.tefway_grant` exists and the Client enforces it; the Master side waits on the login flow |
| Verified technician shown in consent | NOT_WIRED — `authorize_login` returns the identity, but the connection does not carry it to the approval window yet |
| Revocation endpoint check while a session is open | NOT_IMPLEMENTED — TTL is the only propagation |
| Two-machine denial evidence | NOT_TESTED |

Because the Master cannot yet obtain a grant, a Tefway Client build rejects
**every** remote login. That is the intended fail-closed state until the
identity service and login surface exist; it is not a regression of stock
RustDesk, which never enters this code.

# CONNECTION-01 — end-to-end encryption and shared screen

## 1. Root cause of "Conexão Insegura"

The warning is produced by the client's own downgrade dialog
(`confirm_insecure_connection`, `src/client.rs:5069`,
`insecure-connection-nocancel-hasclose` / `conn-e2ee-unavailable-tip`). It
appears when `secure_connection` (`src/client.rs:1655`) returns without a
negotiated session key. Reading the function shows five exits that return a
usable stream with `is_secured() == false`:

| # | Condition (inherited RustDesk behaviour) | Log line |
| --- | --- | --- |
| 1 | `signed_id_pk` empty, or it does not verify under the configured server key | `Handshake failed: invalid public key from rendezvous server`, then an empty `Message` |
| 2 | verified peer ID ≠ expected peer ID (TCP/UDP/relay; WebRTC already bails) | `Handshake failed: sign failure` |
| 3 | `SignedId` cannot be decoded under the peer key | `pk mismatch, fall back to non-secure`, then an empty `PublicKey` |
| 4 | unexpected message variant | `Handshake failed: invalid message type` |
| 5 | unparsable message | `Handshake failed: invalid message format` |

Any of these produces exactly the reported symptom: the client keeps working
but cannot claim E2EE. The Tefway builds make it worse than upstream because a
wrong embedded `PUBLIC_KEY` (one build compiled against a different server key)
lands in case 1 or 3 silently.

Candidate evidence to collect on the real deployment (not done here):

1. `PUBLIC_KEY` in `src/tefway.rs` equals the server's
   `/root/rustdesk-server/id_ed25519.pub` (public half only).
2. Master and Client binaries were built from the same commit and carry the same
   key (`strings` on both artefacts).
3. hbbs was started with that key and its log shows the peer registered.
4. The failure repeats on relay **and** on P2P, which separates a key problem
   (both) from a NAT/relay problem (one).

## 2. Change: fail closed for Tefway profiles

`crate::tefway::requires_verified_peer()` is true for Master and Client and
false for stock builds. Each of the five exits above now returns an error
instead of a stream when it is true:

```
Tefway: peer identity could not be verified; refusing the session
Tefway: peer id mismatch; refusing the session
Tefway: peer key mismatch; refusing an unverified session
Tefway: unexpected handshake message; refusing the session
Tefway: malformed handshake; refusing the session
```

`confirm_insecure_connection` returns `false` **before** showing the dialog for
Tefway profiles, so no operator is ever offered "continue anyway". The stock
RustDesk path is byte-for-byte unchanged when the profile is `Standard`.

Consequences, stated plainly:

- A Tefway Master/Client pair with a key mismatch now fails to connect instead
  of connecting unencrypted. That is the requested behaviour, not a regression.
- The security message is never hidden: the failure reaches the existing error
  flow, and the Master surfaces `connectFailed`.
- No downgrade, no "trust anyway" option, no UI switch to re-enable it.

## 3. Verification

| Check | Result |
| --- | --- |
| `cargo check --features flutter --lib --release` | PASS (EXIT 0) |
| `cargo test --lib --release --features flutter tefway::` | PASS (profile tests, incl. `requires_verified_peer` policy) |
| Live handshake, relay | NOT_TESTED |
| Live handshake, P2P | NOT_TESTED |
| Wrong-key build rejected | NOT_TESTED (requires two artefacts with different keys) |
| Generic RustDesk client against Tefway Client | NOT_TESTED (requires the AUTH-01 login flow) |

## 4. Shared screen — diagnosis plan (not executed)

The reported symptoms have different causes and must not be treated as one bug.

### Fedora / KDE Wayland

1. `xdg-desktop-portal` + `xdg-desktop-portal-kde` running, `pipewire` and
   `wireplumber` active; `systemctl --user status` for each.
2. Capture goes through `org.freedesktop.portal.ScreenCast`; the portal dialog
   must be accepted per session. A denied dialog yields a black frame, not an
   error.
3. Check for SELinux denials rather than disabling SELinux:
   `sudo ausearch -m avc -ts recent` and `journalctl -b | grep -i avc`. A denial
   needs a targeted policy fix by the machine's administrator.
4. Multi-monitor: the portal returns one stream per selected monitor; verify the
   stream count and geometry, not just that "a" picture appears.
5. Input: `libei`/`eis` support in the portal version determines whether pointer
   and keyboard can be injected on Wayland. Record the versions.

### Windows

1. Capture of the secure desktop (UAC) is not possible without elevation; the
   UI must say so (it does, as an informational diagnostic).
2. Multi-monitor and DPI: compare `mainGetDisplays()` geometry with the captured
   frame size at 100/125/150% scaling.
3. Reconnect and monitor switching: switch display during a session and verify
   the frame geometry updates rather than truncating.

### Recursive mirroring

Viewing a remote session inside another remote session can legitimately look
"split" or "repeated" (the intermediate tool captures its own window). Reproduce
A→B directly first; if the artefact disappears, it belongs to the intermediate
tool, not to Tefway. Only a difference between the direct and the nested run is
a Tefway defect.

`CONNECTION_CAPTURE = NOT_TESTED`: no session was established in this
environment, so no capture claim is made.

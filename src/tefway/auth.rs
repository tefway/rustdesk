//! Technician authorization for the Tefway Client profile.
//!
//! The rendezvous server only answers "who is at this ID"; it says nothing
//! about whether the person driving that connection is a Tefway technician.
//! This module adds that statement, and it is the only place that decides it.
//!
//! A grant is a short-lived, Ed25519-signed assertion issued by the Tefway
//! identity service and carried in the login request. It binds:
//!
//! * the technician (id, name, role) and their account state,
//! * the controller identity (`my_id` of the connecting Master),
//! * the destination device (`dev`, the Client's own ID),
//! * a single-use nonce,
//! * an issue time and a hard expiry.
//!
//! The Client verifies the signature against a pinned public key and refuses
//! the login on any failure. There is no unauthenticated path: with no trust
//! anchor, no grant, a bad signature, a stale or replayed nonce, or a mismatch
//! on either identity, the session does not start. Stock RustDesk builds never
//! reach this code.
//!
//! The wire format is deliberately simple and versioned so the identity
//! service can be implemented independently of this crate:
//!
//! ```text
//! grant = base64(payload) "." base64(signature)
//! payload = "TEFWAY1" || field_len(u8) || field ...   (fields in order below)
//! ```
//!
//! Only public keys are compiled in. No password, token or private key is ever
//! stored here, and the audit log records decisions and identities, never the
//! grant itself.

use std::{
    collections::HashMap,
    sync::Mutex,
    time::{SystemTime, UNIX_EPOCH},
};

use base::message_proto::LoginRequest;
use hbb_common::{
    base64::{engine::general_purpose::STANDARD as B64, Engine as _},
    log,
    sodiumoxide::crypto::sign,
};

/// Public key of the Tefway identity service, base64 (32-byte Ed25519 key).
/// A public key is not a secret. When the build supplies none, every Tefway
/// login is refused: an unverifiable grant must not become a session.
const AUTH_PUBKEY_B64: Option<&str> = option_env!("TEFWAY_AUTH_PUBKEY");

const GRANT_MAGIC: &[u8] = b"TEFWAY1";

/// Longest grant accepted from the wire, before any parsing work.
const MAX_GRANT_LEN: usize = 4096;
/// Nonces are at least this many bytes so a peer cannot make them collide.
const MIN_NONCE_LEN: usize = 16;
/// Accepted clock skew for a grant issued "in the future".
const MAX_CLOCK_SKEW_SECS: i64 = 60;

/// Identity the Client verified for an incoming session.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Technician {
    pub id: String,
    pub name: String,
    pub role: String,
}

/// Why a login was refused. Kept explicit so the log and the audit trail say
/// which check failed instead of a generic "not allowed".
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Denial {
    NoTrustAnchor,
    MissingGrant,
    MalformedGrant,
    UnsupportedVersion,
    BadSignature,
    Expired,
    NotYetValid,
    WrongDevice,
    WrongController,
    ReplayedNonce,
    TechnicianNotActive,
}

impl Denial {
    pub fn code(self) -> &'static str {
        match self {
            Denial::NoTrustAnchor => "no-trust-anchor",
            Denial::MissingGrant => "missing-grant",
            Denial::MalformedGrant => "malformed-grant",
            Denial::UnsupportedVersion => "unsupported-version",
            Denial::BadSignature => "bad-signature",
            Denial::Expired => "expired",
            Denial::NotYetValid => "not-yet-valid",
            Denial::WrongDevice => "wrong-device",
            Denial::WrongController => "wrong-controller",
            Denial::ReplayedNonce => "replayed-nonce",
            Denial::TechnicianNotActive => "technician-not-active",
        }
    }

    /// Localised text handed to the peer and shown in the Master's error flow.
    pub fn message(self) -> &'static str {
        match self {
            Denial::NoTrustAnchor => {
                "Tefway: esta instalação não confia em nenhum serviço de identidade; atendimento recusado."
            }
            Denial::MissingGrant => {
                "Tefway: o técnico não apresentou autorização assinada; atendimento recusado."
            }
            Denial::MalformedGrant
            | Denial::UnsupportedVersion
            | Denial::BadSignature => {
                "Tefway: a autorização do técnico não pôde ser verificada; atendimento recusado."
            }
            Denial::Expired | Denial::NotYetValid => {
                "Tefway: a autorização do técnico expirou; solicite um novo acesso."
            }
            Denial::WrongDevice => {
                "Tefway: a autorização foi emitida para outro computador; atendimento recusado."
            }
            Denial::WrongController => {
                "Tefway: a autorização não corresponde a este técnico; atendimento recusado."
            }
            Denial::ReplayedNonce => {
                "Tefway: esta autorização já foi utilizada; solicite um novo acesso."
            }
            Denial::TechnicianNotActive => {
                "Tefway: a conta do técnico não está ativa; atendimento recusado."
            }
        }
    }
}

/// A verified grant, after every check passed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerifiedGrant {
    pub technician: Technician,
    pub controller: String,
    pub device: String,
    pub nonce: Vec<u8>,
    pub issued_at: i64,
    pub expires_at: i64,
}

fn read_field<'a>(buf: &'a [u8], pos: &mut usize) -> Result<&'a [u8], Denial> {
    let len = *buf.get(*pos).ok_or(Denial::MalformedGrant)? as usize;
    *pos += 1;
    let end = pos.checked_add(len).ok_or(Denial::MalformedGrant)?;
    let field = buf.get(*pos..end).ok_or(Denial::MalformedGrant)?;
    *pos = end;
    Ok(field)
}

fn read_str(buf: &[u8], pos: &mut usize) -> Result<String, Denial> {
    String::from_utf8(read_field(buf, pos)?.to_vec()).map_err(|_| Denial::MalformedGrant)
}

fn read_i64(buf: &[u8], pos: &mut usize) -> Result<i64, Denial> {
    let bytes = read_field(buf, pos)?;
    let arr: [u8; 8] = bytes.try_into().map_err(|_| Denial::MalformedGrant)?;
    Ok(i64::from_be_bytes(arr))
}

/// Parse the signed payload. Returns every claim plus the exact bytes that the
/// signature covers, so verification never re-serialises (and cannot disagree
/// with what was signed).
fn parse_payload(payload: &[u8]) -> Result<(VerifiedGrant, &[u8]), Denial> {
    if !payload.starts_with(GRANT_MAGIC) {
        return Err(Denial::UnsupportedVersion);
    }
    let mut pos = GRANT_MAGIC.len();
    let technician_id = read_str(payload, &mut pos)?;
    let technician_name = read_str(payload, &mut pos)?;
    let role = read_str(payload, &mut pos)?;
    let state = read_str(payload, &mut pos)?;
    let controller = read_str(payload, &mut pos)?;
    let device = read_str(payload, &mut pos)?;
    let nonce = read_field(payload, &mut pos)?.to_vec();
    let issued_at = read_i64(payload, &mut pos)?;
    let expires_at = read_i64(payload, &mut pos)?;
    let scope = read_str(payload, &mut pos)?;
    if pos != payload.len() {
        return Err(Denial::MalformedGrant);
    }
    if state != "active" {
        return Err(Denial::TechnicianNotActive);
    }
    if nonce.len() < MIN_NONCE_LEN {
        return Err(Denial::MalformedGrant);
    }
    // `scope` is accepted and carried for the consent window; a future revision
    // that restricts permissions will reject unknown scopes here.
    let _ = scope;
    Ok((
        VerifiedGrant {
            technician: Technician {
                id: technician_id,
                name: technician_name,
                role,
            },
            controller,
            device,
            nonce,
            issued_at,
            expires_at,
        },
        payload,
    ))
}

fn decode_grant(grant: &[u8]) -> Result<(Vec<u8>, Vec<u8>), Denial> {
    if grant.is_empty() {
        return Err(Denial::MissingGrant);
    }
    if grant.len() > MAX_GRANT_LEN {
        return Err(Denial::MalformedGrant);
    }
    let text = std::str::from_utf8(grant).map_err(|_| Denial::MalformedGrant)?;
    let (payload_b64, sig_b64) = text.split_once('.').ok_or(Denial::MalformedGrant)?;
    let payload = B64
        .decode(payload_b64)
        .map_err(|_| Denial::MalformedGrant)?;
    let signature = B64.decode(sig_b64).map_err(|_| Denial::MalformedGrant)?;
    Ok((payload, signature))
}

/// Verifies a grant against an explicit trust anchor.
///
/// Pure with respect to the process: it takes the anchor, the expected
/// identities and the clock, which is what makes every denial testable.
pub fn verify_grant(
    grant: &[u8],
    anchor_b64: &str,
    expected_device: &str,
    expected_controller: &str,
    now: i64,
) -> Result<VerifiedGrant, Denial> {
    let anchor = B64
        .decode(anchor_b64.trim())
        .map_err(|_| Denial::NoTrustAnchor)?;
    let public_key =
        sign::PublicKey::from_slice(&anchor).ok_or(Denial::NoTrustAnchor)?;

    let (payload, signature_bytes) = decode_grant(grant)?;
    let signature =
        sign::Signature::from_bytes(&signature_bytes).map_err(|_| Denial::BadSignature)?;
    let (parsed, signed_bytes) = parse_payload(&payload)?;

    // Signature first: nothing in the payload is trusted until it verifies.
    if !sign::verify_detached(&signature, signed_bytes, &public_key) {
        return Err(Denial::BadSignature);
    }

    if parsed.device != expected_device {
        return Err(Denial::WrongDevice);
    }
    if parsed.controller != expected_controller {
        return Err(Denial::WrongController);
    }
    if parsed.issued_at > now + MAX_CLOCK_SKEW_SECS {
        return Err(Denial::NotYetValid);
    }
    if parsed.expires_at <= now {
        return Err(Denial::Expired);
    }
    Ok(parsed)
}

/// Nonces already spent, with the moment they stop mattering.
static SPENT_NONCES: Mutex<Option<HashMap<Vec<u8>, i64>>> = Mutex::new(None);

fn nonce_is_fresh(nonce: &[u8], expires_at: i64, now: i64) -> bool {
    let mut guard = match SPENT_NONCES.lock() {
        Ok(guard) => guard,
        // A poisoned lock means another thread panicked while holding it. Fail
        // closed: refusing a login is recoverable, replaying a grant is not.
        Err(_) => return false,
    };
    let spent = guard.get_or_insert_with(HashMap::new);
    spent.retain(|_, expiry| *expiry > now);
    if spent.contains_key(nonce) {
        return false;
    }
    spent.insert(nonce.to_vec(), expires_at);
    true
}

/// Reads the pinned anchor of this build.
pub fn trust_anchor() -> Option<&'static str> {
    AUTH_PUBKEY_B64.filter(|key| !key.trim().is_empty())
}

fn app_dir() -> Option<std::path::PathBuf> {
    let dir = hbb_common::config::APP_DIR.read().ok()?.clone();
    if dir.is_empty() {
        return None;
    }
    Some(std::path::PathBuf::from(dir))
}

/// Appends one JSON line to the audit log. Records the decision, the claimed
/// and verified identities, and never the grant or any credential.
pub fn audit(event: &str, peer_id: &str, grant: Option<&VerifiedGrant>, detail: &str) {
    let Some(dir) = app_dir() else {
        log::trace!("tefway audit skipped: no app dir ({event})");
        return;
    };
    let record = serde_json::json!({
        "ts": now_unix(),
        "event": event,
        "peer": peer_id,
        "technician_id": grant.map(|g| g.technician.id.clone()).unwrap_or_default(),
        "technician_name": grant.map(|g| g.technician.name.clone()).unwrap_or_default(),
        "role": grant.map(|g| g.technician.role.clone()).unwrap_or_default(),
        "device": grant.map(|g| g.device.clone()).unwrap_or_default(),
        "grant_expires_at": grant.map(|g| g.expires_at).unwrap_or(0),
        "detail": detail,
    });
    let line = format!("{record}\n");
    let path = dir.join("tefway-auth-audit.log");
    if let Err(err) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .and_then(|mut f| {
            use std::io::Write as _;
            f.write_all(line.as_bytes())
        })
    {
        log::warn!("tefway audit could not be written: {err}");
    }
}

pub fn now_unix() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// The decision point called by the server connection before a login is
/// accepted. It is the only gate, and it denies unless every check passes.
pub fn authorize_login(lr: &LoginRequest, device_id: &str) -> Result<VerifiedGrant, Denial> {
    let anchor = trust_anchor().ok_or(Denial::NoTrustAnchor)?;
    let grant = verify_grant(
        &lr.tefway_grant,
        anchor,
        device_id,
        &lr.my_id,
        now_unix(),
    )?;
    if !nonce_is_fresh(&grant.nonce, grant.expires_at, now_unix()) {
        return Err(Denial::ReplayedNonce);
    }
    Ok(grant)
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::sodiumoxide::crypto::sign;

    struct Issuer {
        public_b64: String,
        secret: sign::SecretKey,
    }

    fn issuer() -> Issuer {
        let (public, secret) = sign::gen_keypair();
        Issuer {
            public_b64: B64.encode(public.as_ref()),
            secret,
        }
    }

    fn field(out: &mut Vec<u8>, bytes: &[u8]) {
        assert!(bytes.len() < 256, "test payload fields stay short");
        out.push(bytes.len() as u8);
        out.extend_from_slice(bytes);
    }

    fn payload(
        technician: &str,
        role: &str,
        state: &str,
        controller: &str,
        device: &str,
        nonce: &[u8],
        issued_at: i64,
        expires_at: i64,
    ) -> Vec<u8> {
        let mut out = GRANT_MAGIC.to_vec();
        field(&mut out, technician.as_bytes());
        field(&mut out, b"Ana Souza");
        field(&mut out, role.as_bytes());
        field(&mut out, state.as_bytes());
        field(&mut out, controller.as_bytes());
        field(&mut out, device.as_bytes());
        field(&mut out, nonce);
        field(&mut out, &issued_at.to_be_bytes());
        field(&mut out, &expires_at.to_be_bytes());
        field(&mut out, b"remote");
        out
    }

    fn signed(issuer: &Issuer, payload: &[u8]) -> Vec<u8> {
        let signature = sign::sign_detached(payload, &issuer.secret);
        format!("{}.{}", B64.encode(payload), B64.encode(signature.as_ref())).into_bytes()
    }

    fn valid_grant(issuer: &Issuer, now: i64) -> Vec<u8> {
        let p = payload("tec-1", "technician", "active", "555111", "777222", &[7u8; 16], now - 5, now + 120);
        signed(issuer, &p)
    }

    #[test]
    fn accepts_a_grant_that_binds_technician_device_and_controller() {
        let issuer = issuer();
        let now = 1_000;
        let grant = verify_grant(&valid_grant(&issuer, now), &issuer.public_b64, "777222", "555111", now)
            .expect("valid grant");
        assert_eq!(grant.technician.id, "tec-1");
        assert_eq!(grant.technician.name, "Ana Souza");
        assert_eq!(grant.device, "777222");
        assert_eq!(grant.controller, "555111");
    }

    #[test]
    fn refuses_an_expired_grant() {
        let issuer = issuer();
        let p = payload("tec-1", "technician", "active", "555111", "777222", &[1u8; 16], 1_000, 1_100);
        let grant = signed(&issuer, &p);
        assert_eq!(
            verify_grant(&grant, &issuer.public_b64, "777222", "555111", 1_100).unwrap_err(),
            Denial::Expired
        );
    }

    #[test]
    fn refuses_a_grant_issued_for_another_device() {
        let issuer = issuer();
        let now = 2_000;
        assert_eq!(
            verify_grant(&valid_grant(&issuer, now), &issuer.public_b64, "999999", "555111", now)
                .unwrap_err(),
            Denial::WrongDevice
        );
    }

    #[test]
    fn refuses_a_grant_issued_for_another_controller() {
        let issuer = issuer();
        let now = 3_000;
        assert_eq!(
            verify_grant(&valid_grant(&issuer, now), &issuer.public_b64, "777222", "123123", now)
                .unwrap_err(),
            Denial::WrongController
        );
    }

    #[test]
    fn refuses_a_tampered_payload() {
        let issuer = issuer();
        let now = 4_000;
        let mut grant = valid_grant(&issuer, now);
        // Flip a character of the base64 payload; the signature no longer covers it.
        let pos = grant.iter().position(|b| *b == b'T').unwrap_or(0);
        grant[pos] = if grant[pos] == b'T' { b'U' } else { b'T' };
        let denial =
            verify_grant(&grant, &issuer.public_b64, "777222", "555111", now).unwrap_err();
        assert!(
            denial == Denial::BadSignature || denial == Denial::MalformedGrant,
            "unexpected denial: {denial:?}"
        );
    }

    #[test]
    fn refuses_a_grant_signed_by_another_key() {
        let issuer = issuer();
        let other = self::issuer();
        let now = 5_000;
        assert_eq!(
            verify_grant(&valid_grant(&other, now), &issuer.public_b64, "777222", "555111", now)
                .unwrap_err(),
            Denial::BadSignature
        );
    }

    #[test]
    fn refuses_a_revoked_or_suspended_technician() {
        let issuer = issuer();
        let now = 6_000;
        let p = payload("tec-1", "technician", "revoked", "555111", "777222", &[9u8; 16], now - 1, now + 60);
        let grant = signed(&issuer, &p);
        assert_eq!(
            verify_grant(&grant, &issuer.public_b64, "777222", "555111", now).unwrap_err(),
            Denial::TechnicianNotActive
        );
    }

    #[test]
    fn refuses_a_missing_grant() {
        let issuer = issuer();
        assert_eq!(
            verify_grant(b"", &issuer.public_b64, "777222", "555111", 1).unwrap_err(),
            Denial::MissingGrant
        );
    }

    #[test]
    fn refuses_when_the_build_has_no_trust_anchor() {
        let issuer = issuer();
        let now = 7_000;
        assert_eq!(
            verify_grant(&valid_grant(&issuer, now), "not-a-key", "777222", "555111", now)
                .unwrap_err(),
            Denial::NoTrustAnchor
        );
    }

    #[test]
    fn a_nonce_cannot_be_spent_twice() {
        let nonce = [42u8; 16];
        assert!(nonce_is_fresh(&nonce, now_unix() + 60, now_unix()));
        assert!(!nonce_is_fresh(&nonce, now_unix() + 60, now_unix()));
    }

    #[test]
    fn an_expired_nonce_does_not_block_a_new_one() {
        let now = now_unix();
        assert!(nonce_is_fresh(&[1u8; 16], now - 1, now));
        // The prune drops the expired entry, so the same nonce is fresh again
        // once its own grant has expired; the grant itself is rejected first.
        assert!(nonce_is_fresh(&[1u8; 16], now + 60, now));
    }
}

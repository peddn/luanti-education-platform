//! What the engine stores of a password: a salt and an SRP verifier.
//!
//! The backend makes up the start passwords of teachers. It works out
//! this entry itself and sends only that to the worlds, so every world
//! has the same one and the password never leaves the backend. The
//! steps follow the engine (SRP-6a with SHA-256 and the 2048 bit group
//! of RFC 5054), or nobody could log in.

use base64::engine::general_purpose::STANDARD_NO_PAD;
use base64::Engine;
use num_bigint::BigUint;
use sha2::{Digest, Sha256};

/// The 2048 bit group of RFC 5054, as the engine has it.
const GROUP: &str = "AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC319294\
    3DB56050A37329CBB4A099ED8193E0757767A13DD52312AB4B03310D\
    CD7F48A9DA04FD50E8083969EDB767B0CF6095179A163AB3661A05FB\
    D5FAAAE82918A9962F0B93B855F97993EC975EEAA80D740ADBF4FF74\
    7359D041D5C33EA71D281E446B14773BCA97B43A23FB801676BD207A\
    436C6481F1D2B9078717461A5B9D32E688F87748544523B524B0D57D\
    5EA77A2775D2ECFA032CFBDBF52FB3786160279004E57AE6AF874E73\
    03CE53299CCC041C7BC308D82A5698F3A8D0C38271AE35F8E9DBFBB6\
    94B5C803D89F7AE435DE236D525F54759B65E372FCD68EF20FA7111F\
    9E4AFF73";
const GENERATOR: u32 = 2;
const SALT_BYTES: usize = 16;

/// Returns the entry for an account and its password, with a new salt.
pub fn entry(name: &str, password: &str) -> String {
    let mut salt = [0u8; SALT_BYTES];
    getrandom::fill(&mut salt).expect("the system has no source of randomness");
    entry_with(name, password, &salt)
}

fn entry_with(name: &str, password: &str, salt: &[u8]) -> String {
    // The engine takes the name in lower case.
    let mut inner = Sha256::new();
    inner.update(name.to_ascii_lowercase().as_bytes());
    inner.update(b":");
    inner.update(password.as_bytes());
    let mut outer = Sha256::new();
    outer.update(salt);
    outer.update(inner.finalize());
    let x = BigUint::from_bytes_be(&outer.finalize());
    let group = BigUint::parse_bytes(GROUP.as_bytes(), 16).expect("the group is a number");
    let verifier = BigUint::from(GENERATOR).modpow(&x, &group);
    format!(
        "#1#{}#{}",
        STANDARD_NO_PAD.encode(salt),
        STANDARD_NO_PAD.encode(verifier.to_bytes_be())
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_entry_has_its_own_salt() {
        let first = entry("frau_meier", "wolke-apfel-47");
        let second = entry("frau_meier", "wolke-apfel-47");
        assert!(first.starts_with("#1#"));
        assert_ne!(first, second);
        assert_eq!(first.split('#').count(), 4);
    }

    #[test]
    fn the_name_counts_in_lower_case() {
        let salt = [7u8; SALT_BYTES];
        assert_eq!(
            entry_with("Frau_Meier", "wolke-apfel-47", &salt),
            entry_with("frau_meier", "wolke-apfel-47", &salt)
        );
        assert_ne!(
            entry_with("frau_meier", "wolke-apfel-47", &salt),
            entry_with("frau_meier", "wolke-apfel-48", &salt)
        );
    }
}

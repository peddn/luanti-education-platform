//! Keys of the worlds. A key is a long random text. The database only
//! holds its hash, so a copy of the database opens no door.

use sha2::{Digest, Sha256};

const KEY_BYTES: usize = 32;
/// Marks a text as a key of a world, so it is recognised when it turns up
/// somewhere it should not be.
const PREFIX: &str = "lepw_";

/// Makes up a new key.
pub fn generate() -> String {
    random(PREFIX)
}

/// Makes up a long random text that starts with `prefix`. It is used for
/// everything that opens a door: keys of worlds, links in mails.
pub fn random(prefix: &str) -> String {
    let mut bytes = [0u8; KEY_BYTES];
    getrandom::fill(&mut bytes).expect("the system has no source of randomness");
    format!("{prefix}{}", hex::encode(bytes))
}

/// Returns what is stored for a key. Keys are random and long, so a plain
/// hash is enough: there is nothing to guess.
pub fn hash(key: &str) -> String {
    hex::encode(Sha256::digest(key.as_bytes()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_are_long_and_differ() {
        let first = generate();
        let second = generate();
        assert!(first.starts_with(PREFIX));
        assert_eq!(first.len(), PREFIX.len() + 2 * KEY_BYTES);
        assert_ne!(first, second);
    }

    #[test]
    fn the_hash_is_stable_and_not_the_key() {
        let key = "lepw_example";
        assert_eq!(hash(key), hash(key));
        assert_ne!(hash(key), key);
        assert_ne!(hash(key), hash("lepw_other"));
        assert_eq!(hash(key).len(), 64);
    }
}

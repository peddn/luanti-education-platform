//! Account names and start passwords for students.
//!
//! An account name is an adjective and a noun, like `klugeEule`. It is
//! made up, so it says nothing about the person. The word lists are kept
//! by hand: only friendly words, and no pair that sounds like mockery.
//! All words are plain ASCII, because the engine allows nothing else in
//! a name and children have to type them.

/// Longest account name. The engine takes 20 characters (tried with
/// Luanti 5.18); one is left as a margin.
pub const MAX_NAME: usize = 19;

/// Grammatical gender of a noun. The ending of the adjective follows it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Gender {
    Masculine,
    Feminine,
    Neuter,
}

impl Gender {
    /// Ending of an adjective before a noun without an article:
    /// kluger Fuchs, kluge Eule, kluges Reh.
    fn ending(self) -> &'static str {
        match self {
            Self::Masculine => "er",
            Self::Feminine => "e",
            Self::Neuter => "es",
        }
    }
}

use Gender::{Feminine as F, Masculine as M, Neuter as N};

/// Adjectives in their base form. Each takes the endings -er, -e and -es
/// without changing its stem, so none ends in -e or -el.
pub const ADJECTIVES: &[&str] = &[
    "achtsam",
    "bunt",
    "ehrlich",
    "eifrig",
    "emsig",
    "fair",
    "fein",
    "findig",
    "flink",
    "freundlich",
    "froh",
    "funkelnd",
    "geduldig",
    "gelassen",
    "geschickt",
    "golden",
    "heiter",
    "hell",
    "herzlich",
    "klar",
    "klug",
    "lachend",
    "leuchtend",
    "lieb",
    "luftig",
    "lustig",
    "mild",
    "munter",
    "mutig",
    "nett",
    "neugierig",
    "pfiffig",
    "rasch",
    "ruhig",
    "sanft",
    "schlau",
    "schnell",
    "silbern",
    "singend",
    "sonnig",
    "sorgsam",
    "stark",
    "strahlend",
    "tanzend",
    "tapfer",
    "treu",
    "wach",
    "wachsam",
    "wacker",
    "wendig",
    "zufrieden",
];

/// Nouns with their gender: animals, plants and things of nature.
pub const NOUNS: &[(&str, Gender)] = &[
    ("Adler", M),
    ("Ahorn", M),
    ("Amsel", F),
    ("Antilope", F),
    ("Bach", M),
    ("Baum", M),
    ("Berg", M),
    ("Biber", M),
    ("Biene", F),
    ("Birke", F),
    ("Blatt", N),
    ("Blume", F),
    ("Boot", N),
    ("Dachs", M),
    ("Delfin", M),
    ("Eiche", F),
    ("Elch", M),
    ("Eule", F),
    ("Falke", M),
    ("Feder", F),
    ("Feuer", N),
    ("Fink", M),
    ("Flamme", F),
    ("Fohlen", N),
    ("Forelle", F),
    ("Fuchs", M),
    ("Funke", M),
    ("Gazelle", F),
    ("Giraffe", F),
    ("Grille", F),
    ("Hamster", M),
    ("Hase", M),
    ("Hirsch", M),
    ("Hummel", F),
    ("Igel", M),
    ("Insel", F),
    ("Katze", F),
    ("Kiesel", M),
    ("Koala", M),
    ("Komet", M),
    ("Kranich", M),
    ("Kristall", M),
    ("Lama", N),
    ("Lerche", F),
    ("Libelle", F),
    ("Licht", N),
    ("Linde", F),
    ("Luchs", M),
    ("Marder", M),
    ("Meer", N),
    ("Meise", F),
    ("Mond", M),
    ("Otter", M),
    ("Panda", M),
    ("Perle", F),
    ("Pinguin", M),
    ("Pony", N),
    ("Quelle", F),
    ("Rabe", M),
    ("Reh", N),
    ("Robbe", F),
    ("Schwalbe", F),
    ("Seepferd", N),
    ("Segel", N),
    ("Sonne", F),
    ("Spatz", M),
    ("Specht", M),
    ("Stern", M),
    ("Storch", M),
    ("Tanne", F),
    ("Taube", F),
    ("Tiger", M),
    ("Wal", M),
    ("Welle", F),
    ("Wiese", F),
    ("Wiesel", N),
    ("Wind", M),
    ("Wolf", M),
    ("Wolke", F),
    ("Zebra", N),
];

/// Words for start passwords: short, common, easy to type and to read
/// out. No word needs a capital letter here.
pub const PASSWORD_WORDS: &[&str] = &[
    "apfel", "ball", "baum", "berg", "birne", "blatt", "blume", "boot", "brot", "buch", "burg",
    "dach", "dorf", "eis", "erde", "fahne", "feder", "feld", "fenster", "feuer", "fisch", "garten",
    "glas", "gras", "hafen", "haus", "himmel", "holz", "hut", "insel", "kerze", "kiste", "korb",
    "kreis", "krone", "kuchen", "lampe", "licht", "luft", "meer", "mond", "nacht", "nebel", "nest",
    "papier", "pferd", "pilz", "regen", "ring", "rose", "sand", "schiff", "schnee", "see", "seil",
    "sonne", "stein", "stern", "strand", "tal", "tanne", "tisch", "tor", "turm", "ufer", "wald",
    "wasser", "weg", "welle", "wiese", "wind", "wolke", "zelt", "zug",
];

/// Builds the account name from an adjective and a noun: the adjective
/// in small letters with its ending, then the noun as it is written.
pub fn account_name(adjective: &str, noun: &str, gender: Gender) -> String {
    format!("{adjective}{}{noun}", gender.ending())
}

/// Returns a number below `bound`, from the randomness of the system.
fn random_below(bound: usize) -> usize {
    let mut bytes = [0u8; 8];
    getrandom::fill(&mut bytes).expect("the system has no source of randomness");
    // The lists are tiny against 2^64, so the remainder is fair enough.
    (u64::from_le_bytes(bytes) % bound as u64) as usize
}

/// Rolls an account name. It can be taken already; the caller checks
/// and rolls again.
pub fn roll_account_name() -> String {
    loop {
        let adjective = ADJECTIVES[random_below(ADJECTIVES.len())];
        let (noun, gender) = NOUNS[random_below(NOUNS.len())];
        let name = account_name(adjective, noun, gender);
        if name.len() <= MAX_NAME {
            return name;
        }
    }
}

/// Rolls a start password: two words and two digits, like
/// `wolke-apfel-47`. Children have to type it, so it is easy rather than
/// strong, and meant to be changed.
pub fn roll_password() -> String {
    let first = PASSWORD_WORDS[random_below(PASSWORD_WORDS.len())];
    let second = loop {
        let word = PASSWORD_WORDS[random_below(PASSWORD_WORDS.len())];
        if word != first {
            break word;
        }
    };
    format!("{first}-{second}-{:02}", random_below(100))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    fn plain(word: &str) -> bool {
        word.chars().all(|c| c.is_ascii_alphabetic())
    }

    #[test]
    fn builds_names_with_the_right_ending() {
        assert_eq!(account_name("klug", "Fuchs", M), "klugerFuchs");
        assert_eq!(account_name("klug", "Eule", F), "klugeEule");
        assert_eq!(account_name("klug", "Reh", N), "klugesReh");
        assert_eq!(account_name("munter", "Dachs", M), "muntererDachs");
        assert_eq!(account_name("lachend", "Wolke", F), "lachendeWolke");
    }

    #[test]
    fn the_adjectives_fit_the_rules() {
        let mut seen = HashSet::new();
        for adjective in ADJECTIVES {
            assert!(plain(adjective), "{adjective}");
            assert_eq!(*adjective, adjective.to_lowercase(), "{adjective}");
            // These would need a changed stem: leise -> leiser, dunkel -> dunkler.
            assert!(
                !adjective.ends_with('e') && !adjective.ends_with("el"),
                "{adjective}"
            );
            assert!(seen.insert(adjective), "{adjective} is listed twice");
        }
        assert!(ADJECTIVES.len() >= 50);
    }

    #[test]
    fn the_nouns_fit_the_rules() {
        let mut seen = HashSet::new();
        for (noun, _) in NOUNS {
            assert!(plain(noun), "{noun}");
            let mut letters = noun.chars();
            assert!(letters.next().unwrap().is_ascii_uppercase(), "{noun}");
            assert!(letters.all(|c| c.is_ascii_lowercase()), "{noun}");
            assert!(seen.insert(noun), "{noun} is listed twice");
        }
        assert!(NOUNS.len() >= 80);
    }

    #[test]
    fn there_are_enough_names_for_a_school() {
        let mut names = HashSet::new();
        for adjective in ADJECTIVES {
            for (noun, gender) in NOUNS {
                let name = account_name(adjective, noun, *gender);
                if name.len() <= MAX_NAME {
                    // No two pairs give the same name, in any letter case.
                    assert!(names.insert(name.to_lowercase()), "{name}");
                }
            }
        }
        assert!(names.len() >= 3000, "only {} names", names.len());
    }

    #[test]
    fn rolled_names_are_names_the_engine_takes() {
        for _ in 0..500 {
            let name = roll_account_name();
            assert!(name.len() <= MAX_NAME && name.len() >= 5, "{name}");
            assert!(plain(&name), "{name}");
            assert!(name.chars().next().unwrap().is_ascii_lowercase(), "{name}");
            assert_eq!(
                name.chars().filter(char::is_ascii_uppercase).count(),
                1,
                "{name}"
            );
        }
    }

    #[test]
    fn rolling_does_not_repeat_itself() {
        let names: HashSet<String> = (0..200).map(|_| roll_account_name()).collect();
        assert!(names.len() > 150, "only {} different names", names.len());
        let passwords: HashSet<String> = (0..200).map(|_| roll_password()).collect();
        assert!(
            passwords.len() > 190,
            "only {} different passwords",
            passwords.len()
        );
    }

    #[test]
    fn passwords_are_two_words_and_two_digits() {
        let mut seen = HashSet::new();
        for word in PASSWORD_WORDS {
            assert!(word.chars().all(|c| c.is_ascii_lowercase()), "{word}");
            assert!(word.len() >= 3 && word.len() <= 7, "{word}");
            assert!(seen.insert(word), "{word} is listed twice");
        }
        for _ in 0..200 {
            let password = roll_password();
            let parts: Vec<&str> = password.split('-').collect();
            assert_eq!(parts.len(), 3, "{password}");
            assert!(PASSWORD_WORDS.contains(&parts[0]), "{password}");
            assert!(PASSWORD_WORDS.contains(&parts[1]), "{password}");
            assert_ne!(parts[0], parts[1], "{password}");
            assert_eq!(parts[2].len(), 2, "{password}");
            assert!(parts[2].chars().all(|c| c.is_ascii_digit()), "{password}");
        }
    }
}

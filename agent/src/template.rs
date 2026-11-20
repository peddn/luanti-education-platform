//! The template for worlds: the game and all mods, packed into the agent
//! when it was built. The agent unpacks it once into its folder
//! `templates/<version>/`, and every world points to one version.
//!
//! The agent only ever unpacks its own archive. It still trusts no path
//! in it: nothing is written outside the folder of the version.

use std::collections::BTreeMap;
use std::fs;
use std::io::{self, Read};
use std::os::unix::fs::PermissionsExt;
use std::path::{Component, Path, PathBuf};

use anyhow::{bail, Context, Result};
use flate2::read::GzDecoder;
use sha2::{Digest, Sha256};

/// File in a template that lists every other file with its checksum.
pub const FILE_LIST: &str = "files.sha256";
/// File in a template that says what is inside.
pub const MANIFEST: &str = "template.toml";
/// Folder below the folder of the agent that holds the templates.
pub const FOLDER: &str = "templates";

/// A packed template.
#[derive(Clone, Copy)]
pub struct Template<'a> {
    /// Start of the checksum of the file list. The same content gives the
    /// same version.
    pub version: &'a str,
    /// The archive, a gzipped tar.
    pub archive: &'a [u8],
}

/// The template this agent was built with, if it was built with one.
#[cfg(lep_template)]
pub fn embedded() -> Option<Template<'static>> {
    // A static, so the program holds the archive exactly once.
    static ARCHIVE: &[u8] = include_bytes!(env!("LEP_TEMPLATE_ARCHIVE"));
    Some(Template {
        version: env!("LEP_TEMPLATE_VERSION"),
        archive: ARCHIVE,
    })
}

/// The template this agent was built with, if it was built with one.
#[cfg(not(lep_template))]
pub fn embedded() -> Option<Template<'static>> {
    None
}

/// What `ensure` found and did.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    /// The template was there and complete.
    Present,
    /// The template was unpacked.
    Unpacked,
    /// The template was there but damaged, and was unpacked again.
    Repaired,
}

/// Makes sure the template lies unpacked and complete in the folder of
/// the agent. Returns its folder.
pub fn ensure(data_dir: &Path, template: Template<'_>) -> Result<(PathBuf, Outcome)> {
    check_version(template.version)?;
    let templates = data_dir.join(FOLDER);
    let target = templates.join(template.version);
    let mut outcome = Outcome::Unpacked;
    if target.exists() {
        if verify(&target, template.version).is_ok() {
            return Ok((target, Outcome::Present));
        }
        outcome = Outcome::Repaired;
    }

    fs::create_dir_all(&templates)
        .with_context(|| format!("cannot create {}", templates.display()))?;
    // Unpacked next to its place and moved there in one step, so a
    // template that is there is never half a template.
    let fresh = templates.join(format!(".unpacking-{}", template.version));
    remove_if_there(&fresh)?;
    unpack(template.archive, &fresh)
        .and_then(|()| verify(&fresh, template.version))
        .with_context(|| format!("cannot unpack the template into {}", fresh.display()))?;
    if target.exists() {
        let damaged = templates.join(format!(".damaged-{}", template.version));
        remove_if_there(&damaged)?;
        fs::rename(&target, &damaged)
            .with_context(|| format!("cannot move {} away", target.display()))?;
        fs::rename(&fresh, &target)
            .with_context(|| format!("cannot move the template to {}", target.display()))?;
        remove_if_there(&damaged)?;
    } else {
        fs::rename(&fresh, &target)
            .with_context(|| format!("cannot move the template to {}", target.display()))?;
    }
    Ok((target, outcome))
}

/// A version is part of a path, so it must be nothing but a plain name.
fn check_version(version: &str) -> Result<()> {
    if version.is_empty() || !version.chars().all(|c| c.is_ascii_hexdigit()) {
        bail!("'{version}' is not a version of a template");
    }
    Ok(())
}

fn remove_if_there(path: &Path) -> Result<()> {
    match fs::remove_dir_all(path) {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(err).with_context(|| format!("cannot remove {}", path.display())),
    }
}

/// Turns a path from the archive or the file list into one below the
/// folder of the template. Anything that could lead elsewhere is
/// refused.
fn inside(path: &Path) -> Result<PathBuf> {
    let mut clean = PathBuf::new();
    for part in path.components() {
        match part {
            Component::CurDir => {}
            Component::Normal(name) => clean.push(name),
            _ => bail!("the path {} leaves the template", path.display()),
        }
    }
    Ok(clean)
}

/// Unpacks an archive into a new folder. Only folders and plain files
/// are taken, no links and nothing special.
fn unpack(archive: &[u8], folder: &Path) -> Result<()> {
    fs::create_dir(folder)?;
    let mut tar = tar::Archive::new(GzDecoder::new(archive));
    for entry in tar.entries().context("the archive cannot be read")? {
        let mut entry = entry.context("the archive cannot be read")?;
        let path = inside(&entry.path()?)?;
        if path.as_os_str().is_empty() {
            continue;
        }
        let target = folder.join(&path);
        let kind = entry.header().entry_type();
        if kind.is_dir() {
            fs::create_dir_all(&target)?;
        } else if kind.is_file() {
            if let Some(parent) = target.parent() {
                fs::create_dir_all(parent)?;
            }
            let mut file = fs::File::create_new(&target)
                .with_context(|| format!("cannot write {}", path.display()))?;
            io::copy(&mut entry, &mut file)?;
            // Nothing in a template is a program.
            file.set_permissions(fs::Permissions::from_mode(0o644))?;
        } else {
            bail!("{} is neither a file nor a folder", path.display());
        }
    }
    Ok(())
}

/// Reads a file list: one line per file, checksum and path as
/// `sha256sum` writes them.
fn parse_file_list(text: &str) -> Result<BTreeMap<PathBuf, String>> {
    let mut files = BTreeMap::new();
    for line in text.lines().filter(|line| !line.is_empty()) {
        let (sum, path) = line
            .split_once("  ")
            .filter(|(sum, _)| sum.len() == 64 && sum.chars().all(|c| c.is_ascii_hexdigit()))
            .context("a line of the file list cannot be read")?;
        files.insert(inside(Path::new(path))?, sum.to_ascii_lowercase());
    }
    if files.is_empty() {
        bail!("the file list is empty");
    }
    Ok(files)
}

fn checksum(path: &Path) -> Result<String> {
    let mut file = fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(hex::encode(hasher.finalize()))
}

/// Checks that an unpacked template is the given version and complete:
/// every file of its list is there and unchanged.
pub fn verify(folder: &Path, version: &str) -> Result<()> {
    let list = fs::read(folder.join(FILE_LIST)).context("the file list is missing")?;
    if !hex::encode(Sha256::digest(&list)).starts_with(&version.to_ascii_lowercase()) {
        bail!("the file list does not belong to version {version}");
    }
    let files = parse_file_list(std::str::from_utf8(&list).context("the file list is no text")?)?;
    if !files.contains_key(Path::new(MANIFEST)) {
        bail!("the template has no {MANIFEST}");
    }
    for (path, expected) in &files {
        let found = checksum(&folder.join(path))
            .with_context(|| format!("{} is missing", path.display()))?;
        if &found != expected {
            bail!("{} was changed", path.display());
        }
    }
    Ok(())
}

/// Builds small templates for tests.
#[cfg(test)]
pub(crate) mod testing {
    use super::*;
    use flate2::write::GzEncoder;
    use flate2::Compression;

    /// Packs files into an archive, with a correct file list. Returns
    /// the version and the archive.
    pub fn pack(files: &[(&str, &str)]) -> (String, Vec<u8>) {
        let mut list = String::new();
        for (path, content) in files {
            list.push_str(&format!(
                "{}  ./{path}\n",
                hex::encode(Sha256::digest(content.as_bytes()))
            ));
        }
        let version = hex::encode(Sha256::digest(list.as_bytes()))[..12].to_owned();
        let mut all: Vec<(&str, &str)> = files.to_vec();
        all.push((FILE_LIST, &list));
        (version, pack_raw(&all))
    }

    /// Packs exactly these files, without adding a file list.
    pub fn pack_raw(files: &[(&str, &str)]) -> Vec<u8> {
        let mut tar = tar::Builder::new(GzEncoder::new(Vec::new(), Compression::fast()));
        for (path, content) in files {
            let mut header = tar::Header::new_gnu();
            header.set_size(content.len() as u64);
            header.set_mode(0o755);
            header.set_cksum();
            tar.append_data(&mut header, format!("./{path}"), content.as_bytes())
                .unwrap();
        }
        tar.into_inner().unwrap().finish().unwrap()
    }

    pub const SMALL: &[(&str, &str)] = &[
        (MANIFEST, "[game]\nname = \"minetest_game\"\n"),
        ("games/minetest_game/game.conf", "title = Minetest Game\n"),
        ("mods/lep/lep_core/init.lua", "-- core\n"),
    ];
}

#[cfg(test)]
mod tests {
    use super::testing::{pack, pack_raw, SMALL};
    use super::*;

    #[test]
    fn unpacks_the_template_once() {
        let data = tempfile::tempdir().unwrap();
        let (version, archive) = pack(SMALL);
        let template = Template {
            version: &version,
            archive: &archive,
        };

        let (folder, outcome) = ensure(data.path(), template).unwrap();
        assert_eq!(outcome, Outcome::Unpacked);
        assert_eq!(folder, data.path().join(FOLDER).join(&version));
        assert_eq!(
            fs::read_to_string(folder.join("mods/lep/lep_core/init.lua")).unwrap(),
            "-- core\n"
        );
        // Nothing in a template can be run, whatever the archive says.
        let mode = fs::metadata(folder.join("mods/lep/lep_core/init.lua"))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o644);

        let (again, outcome) = ensure(data.path(), template).unwrap();
        assert_eq!(outcome, Outcome::Present);
        assert_eq!(again, folder);
        // Nothing is left over next to it.
        let names: Vec<_> = fs::read_dir(data.path().join(FOLDER))
            .unwrap()
            .map(|entry| entry.unwrap().file_name())
            .collect();
        assert_eq!(names, [version.as_str()]);
    }

    #[test]
    fn repairs_a_damaged_template() {
        let data = tempfile::tempdir().unwrap();
        let (version, archive) = pack(SMALL);
        let template = Template {
            version: &version,
            archive: &archive,
        };
        let (folder, _) = ensure(data.path(), template).unwrap();

        fs::write(folder.join("mods/lep/lep_core/init.lua"), "-- changed\n").unwrap();
        assert!(verify(&folder, &version).is_err());
        assert_eq!(ensure(data.path(), template).unwrap().1, Outcome::Repaired);
        assert_eq!(
            fs::read_to_string(folder.join("mods/lep/lep_core/init.lua")).unwrap(),
            "-- core\n"
        );

        fs::remove_file(folder.join("games/minetest_game/game.conf")).unwrap();
        assert_eq!(ensure(data.path(), template).unwrap().1, Outcome::Repaired);
        fs::remove_file(folder.join(FILE_LIST)).unwrap();
        assert_eq!(ensure(data.path(), template).unwrap().1, Outcome::Repaired);
        assert_eq!(ensure(data.path(), template).unwrap().1, Outcome::Present);
    }

    #[test]
    fn clears_what_an_interrupted_run_left() {
        let data = tempfile::tempdir().unwrap();
        let (version, archive) = pack(SMALL);
        let leftover = data
            .path()
            .join(FOLDER)
            .join(format!(".unpacking-{version}"));
        fs::create_dir_all(leftover.join("mods")).unwrap();
        fs::write(leftover.join("mods/half.lua"), "x").unwrap();

        let template = Template {
            version: &version,
            archive: &archive,
        };
        let (folder, outcome) = ensure(data.path(), template).unwrap();
        assert_eq!(outcome, Outcome::Unpacked);
        assert!(!leftover.exists());
        assert!(!folder.join("mods/half.lua").exists());
    }

    #[test]
    fn keeps_other_versions() {
        let data = tempfile::tempdir().unwrap();
        let (old, old_archive) = pack(SMALL);
        let mut newer = SMALL.to_vec();
        newer.push(("mods/lep/lep_new/init.lua", "-- new\n"));
        let (new, new_archive) = pack(&newer);
        assert_ne!(old, new);

        let template = |version, archive| Template { version, archive };
        let (old_folder, _) = ensure(data.path(), template(&old, &old_archive)).unwrap();
        let (new_folder, _) = ensure(data.path(), template(&new, &new_archive)).unwrap();
        assert!(old_folder.join(MANIFEST).is_file());
        assert!(new_folder.join("mods/lep/lep_new/init.lua").is_file());
    }

    #[test]
    fn refuses_an_archive_that_does_not_fit_its_version() {
        let data = tempfile::tempdir().unwrap();
        let (_, archive) = pack(SMALL);
        let template = Template {
            version: "000000000000",
            archive: &archive,
        };
        assert!(ensure(data.path(), template).is_err());
        assert!(!data.path().join(FOLDER).join("000000000000").exists());

        // A list that names a file the archive does not hold.
        let list = format!("{}  ./{MANIFEST}\n", "0".repeat(64));
        let version = hex::encode(Sha256::digest(list.as_bytes()))[..12].to_owned();
        let archive = pack_raw(&[(FILE_LIST, &list)]);
        let template = Template {
            version: &version,
            archive: &archive,
        };
        assert!(ensure(data.path(), template).is_err());
        assert!(!data.path().join(FOLDER).join(&version).exists());
    }

    #[test]
    fn refuses_versions_that_are_no_plain_name() {
        let data = tempfile::tempdir().unwrap();
        let (_, archive) = pack(SMALL);
        for version in ["", "..", "../x", "ab/cd", "xyz"] {
            let template = Template {
                version,
                archive: &archive,
            };
            assert!(ensure(data.path(), template).is_err(), "{version}");
        }
    }

    #[test]
    fn writes_nothing_outside_its_folder() {
        for path in ["../escaped.txt", "/tmp/lep-escaped.txt", "a/../../b.txt"] {
            assert!(inside(Path::new(path)).is_err(), "{path}");
        }
        assert_eq!(
            inside(Path::new("./mods/lep/init.lua")).unwrap(),
            PathBuf::from("mods/lep/init.lua")
        );
        let list = format!("{}  ../outside\n", "0".repeat(64));
        assert!(parse_file_list(&list).is_err());
    }

    #[test]
    fn takes_no_links() {
        let data = tempfile::tempdir().unwrap();
        let mut tar = tar::Builder::new(flate2::write::GzEncoder::new(
            Vec::new(),
            flate2::Compression::fast(),
        ));
        let mut header = tar::Header::new_gnu();
        header.set_entry_type(tar::EntryType::Symlink);
        header.set_size(0);
        tar.append_link(&mut header, "./link", "/etc/passwd")
            .unwrap();
        let archive = tar.into_inner().unwrap().finish().unwrap();
        let template = Template {
            version: "abc123",
            archive: &archive,
        };
        assert!(ensure(data.path(), template).is_err());
        assert!(!data.path().join(FOLDER).join("abc123").exists());
    }

    #[test]
    fn reads_the_file_list() {
        let sum = "a".repeat(64);
        let files = parse_file_list(&format!("{sum}  ./a/b.txt\n{sum}  ./c.txt\n")).unwrap();
        assert_eq!(files.len(), 2);
        assert!(files.contains_key(Path::new("a/b.txt")));
        assert!(parse_file_list("").is_err());
        assert!(parse_file_list("not a list\n").is_err());
        assert!(parse_file_list(&format!("{}  ./short\n", "a".repeat(10))).is_err());
    }
}

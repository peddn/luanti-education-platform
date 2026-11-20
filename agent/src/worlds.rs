//! The worlds on the game server, as folders below `worlds/` in the
//! folder of the agent.
//!
//! A folder is named after the fixed identifier of its world and holds:
//!
//! - `lep-world.toml`: the note of the agent, with port and template
//! - `minetest.conf`: the settings of the world, with the key of the
//!   bridge
//! - `world/`: what Luanti keeps, map and players
//! - `games`, `mods`: links to the template the world uses
//!
//! Every path is built from an identifier that was checked. Nothing else
//! from a job ends up in a path.

use std::collections::BTreeSet;
use std::fmt;
use std::fs;
use std::io::Write;
use std::ops::RangeInclusive;
use std::os::unix::fs::{symlink, OpenOptionsExt};
use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};
use lep_protocol::agent::WorldState;
use serde::{Deserialize, Serialize};

use crate::template::Manifest;

/// Folder below the folder of the agent that holds the worlds.
pub const FOLDER: &str = "worlds";
/// File in the folder of a world with the note of the agent.
const NOTE: &str = "lep-world.toml";
/// File in the folder of a world with its settings.
pub const SETTINGS: &str = "minetest.conf";
/// Start of every key of a world.
const KEY_PREFIX: &str = "lepw_";

/// The fixed identifier of a world, in the form the backend gives it:
/// `8-4-4-4-12` hexadecimal digits. It is safe as the name of a folder.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct WorldId(String);

impl WorldId {
    pub fn parse(text: &str) -> Result<Self> {
        let groups: Vec<&str> = text.split('-').collect();
        let fits = groups.len() == 5
            && groups.iter().zip([8, 4, 4, 4, 12]).all(|(group, length)| {
                group.len() == length
                    && group
                        .chars()
                        .all(|c| c.is_ascii_digit() || ('a'..='f').contains(&c))
            });
        if !fits {
            bail!("this is not the identifier of a world");
        }
        Ok(Self(text.to_owned()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for WorldId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

/// What the agent notes about a world.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Note {
    /// Port players reach the world on.
    pub port: u16,
    /// Version of the template the world uses.
    pub template: String,
}

/// What a new world is made from.
pub struct Plan<'a> {
    /// Folder of the agent.
    pub data_dir: &'a Path,
    /// Version of the template, and what is in it.
    pub template: &'a str,
    pub manifest: &'a Manifest,
    /// Ports worlds may get.
    pub ports: RangeInclusive<u16>,
    /// Account name of the server admin.
    pub admin: &'a str,
    /// Address of the backend for the bridge, without a slash at the end.
    pub backend: &'a str,
    /// Key the bridge calls the backend with.
    pub bridge_key: &'a str,
}

/// What `create` did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Created {
    /// The world is new.
    New(Note),
    /// The world was there. Only its settings were written again.
    Kept(Note),
}

/// Returns the folder of a world.
pub fn folder(data_dir: &Path, id: &WorldId) -> PathBuf {
    data_dir.join(FOLDER).join(id.as_str())
}

/// Returns the worlds that are there, sorted by identifier. A folder
/// that is no world is left out.
pub fn list(data_dir: &Path) -> Result<Vec<(WorldId, Note)>> {
    let folder = data_dir.join(FOLDER);
    let entries = match fs::read_dir(&folder) {
        Ok(entries) => entries,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(err) => return Err(err).with_context(|| format!("cannot read {}", folder.display())),
    };
    let mut worlds = Vec::new();
    for entry in entries {
        let entry = entry?;
        let Some(id) = entry
            .file_name()
            .to_str()
            .and_then(|name| WorldId::parse(name).ok())
        else {
            continue;
        };
        if let Ok(note) = read_note(&entry.path()) {
            worlds.push((id, note));
        }
    }
    worlds.sort();
    Ok(worlds)
}

/// Returns the worlds as the report to the backend names them.
pub fn states(data_dir: &Path) -> Result<Vec<WorldState>> {
    Ok(list(data_dir)?
        .into_iter()
        .map(|(id, note)| WorldState {
            id: id.as_str().to_owned(),
            port: note.port,
            template: note.template,
        })
        .collect())
}

impl PartialOrd for Note {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Note {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.port.cmp(&other.port)
    }
}

fn read_note(world: &Path) -> Result<Note> {
    let text = fs::read_to_string(world.join(NOTE))?;
    Ok(toml::from_str(&text)?)
}

/// Creates a world. For a world that is there already nothing is
/// created: port, map and players stay, and only the settings are
/// written again with the key from the plan.
pub fn create(id: &WorldId, plan: &Plan<'_>) -> Result<Created> {
    if !plan.bridge_key.starts_with(KEY_PREFIX)
        || !plan
            .bridge_key
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_')
    {
        bail!("the key of the bridge cannot be read");
    }
    let target = folder(plan.data_dir, id);
    if target.exists() {
        let note = read_note(&target)
            .with_context(|| format!("the folder of world {id} is there, but it is no world"))?;
        write_settings(&target, &note, plan)?;
        return Ok(Created::Kept(note));
    }

    let taken: BTreeSet<u16> = list(plan.data_dir)?
        .into_iter()
        .map(|(_, note)| note.port)
        .collect();
    let Some(port) = plan.ports.clone().find(|port| !taken.contains(port)) else {
        bail!(
            "no port is free: all from {} to {} are taken",
            plan.ports.start(),
            plan.ports.end()
        );
    };
    let note = Note {
        port,
        template: plan.template.to_owned(),
    };

    let worlds = plan.data_dir.join(FOLDER);
    fs::create_dir_all(&worlds).with_context(|| format!("cannot create {}", worlds.display()))?;
    // Built next to its place and moved there in one step, so a world
    // that is there is never half a world.
    let fresh = worlds.join(format!(".creating-{id}"));
    match fs::remove_dir_all(&fresh) {
        Ok(()) => {}
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
        Err(err) => return Err(err).with_context(|| format!("cannot remove {}", fresh.display())),
    }
    build(&fresh, &note, plan).with_context(|| format!("cannot create world {id}"))?;
    fs::rename(&fresh, &target)
        .with_context(|| format!("cannot move the world to {}", target.display()))?;
    Ok(Created::New(note))
}

fn build(folder: &Path, note: &Note, plan: &Plan<'_>) -> Result<()> {
    fs::create_dir(folder)?;
    fs::create_dir(folder.join("world"))?;
    fs::write(folder.join("world/world.mt"), world_mt(plan.manifest))?;
    // Relative, so the folder of the agent can be moved as a whole.
    let template = Path::new("../..")
        .join(crate::template::FOLDER)
        .join(&note.template);
    symlink(template.join("games"), folder.join("games"))?;
    symlink(template.join("mods"), folder.join("mods"))?;
    write_settings(folder, note, plan)?;
    fs::write(folder.join(NOTE), toml::to_string(note)?)?;
    Ok(())
}

/// What Luanti needs to know about the world itself: the game, how it
/// stores things, and which mods are on.
fn world_mt(manifest: &Manifest) -> String {
    let mut text = String::from(
        "gameid = minetest\nbackend = sqlite3\nplayer_backend = sqlite3\n\
         auth_backend = sqlite3\nmod_storage_backend = sqlite3\n",
    );
    for name in manifest.mod_names() {
        text.push_str(&format!("load_mod_{name} = true\n"));
    }
    text
}

/// Writes the settings of a world. Only the owner may read them: they
/// hold the key of the bridge.
fn write_settings(folder: &Path, note: &Note, plan: &Plan<'_>) -> Result<()> {
    let mut text = String::from("# Written by the LEP agent. Changes are overwritten.\n");
    let mut line = |key: &str, value: &str| -> Result<()> {
        // A value with a line break could add settings of its own.
        if value.chars().any(char::is_control) {
            bail!("the value of {key} cannot be written");
        }
        text.push_str(&format!("{key} = {value}\n"));
        Ok(())
    };
    line("port", &note.port.to_string())?;
    line("name", plan.admin)?;
    line("server_announce", "false")?;
    line("creative_mode", "false")?;
    line("enable_damage", "true")?;
    for (key, value) in &plan.manifest.settings {
        line(key, value)?;
    }
    line("secure.http_mods", "lep_bridge")?;
    line("lep_bridge_url", plan.backend)?;
    line("lep_bridge_key", plan.bridge_key)?;

    let path = folder.join(SETTINGS);
    let fresh = folder.join(format!(".{SETTINGS}.new"));
    let _ = fs::remove_file(&fresh);
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&fresh)
        .with_context(|| format!("cannot write {}", fresh.display()))?;
    file.write_all(text.as_bytes())?;
    file.sync_all()?;
    fs::rename(&fresh, &path).with_context(|| format!("cannot write {}", path.display()))?;
    Ok(())
}

#[cfg(test)]
pub(crate) mod testing {
    use super::*;

    pub const ID: &str = "0b54f9c6-5f0e-4a3c-9d2e-7a1c0f3b8e21";
    pub const OTHER: &str = "9a8b7c6d-1111-4222-8333-444455556666";

    pub fn manifest() -> Manifest {
        toml::from_str(
            "lep_mods = [\"lep_core\", \"lep_bridge\"]\n[game]\nname = \"minetest_game\"\n\
             [[mods]]\nname = \"protector\"\n[settings]\nprotector_radius = \"8\"\n",
        )
        .unwrap()
    }

    pub fn plan<'a>(data_dir: &'a Path, manifest: &'a Manifest) -> Plan<'a> {
        Plan {
            data_dir,
            template: "bdbbf00c8a29",
            manifest,
            ports: 30000..=30002,
            admin: "peddn",
            backend: "http://127.0.0.1:8080",
            bridge_key: "lepw_0123abcd",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::testing::{manifest, plan, ID, OTHER};
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn only_identifiers_of_the_backend_are_taken() {
        assert!(WorldId::parse(ID).is_ok());
        for text in [
            "",
            "7b",
            "..",
            "../../etc",
            "0b54f9c6-5f0e-4a3c-9d2e-7a1c0f3b8e2",
            "0b54f9c6-5f0e-4a3c-9d2e-7a1c0f3b8e21/",
            "0B54F9C6-5F0E-4A3C-9D2E-7A1C0F3B8E21",
            "0b54f9c6/5f0e-4a3c-9d2e-7a1c0f3b8e21",
            "0b54f9c6-5f0e-4a3c-9d2e-7a1c0f3b8e21\n",
        ] {
            assert!(WorldId::parse(text).is_err(), "{text:?}");
        }
    }

    #[test]
    fn creates_a_world_with_everything_luanti_needs() {
        let data = tempfile::tempdir().unwrap();
        let manifest = manifest();
        let id = WorldId::parse(ID).unwrap();

        let created = create(&id, &plan(data.path(), &manifest)).unwrap();
        let note = Note {
            port: 30000,
            template: "bdbbf00c8a29".to_owned(),
        };
        assert_eq!(created, Created::New(note.clone()));

        let world = folder(data.path(), &id);
        assert_eq!(world, data.path().join("worlds").join(ID));
        let world_mt = fs::read_to_string(world.join("world/world.mt")).unwrap();
        assert!(world_mt.contains("gameid = minetest\n"));
        for name in ["lep_core", "lep_bridge", "protector"] {
            assert!(world_mt.contains(&format!("load_mod_{name} = true\n")));
        }
        let settings = fs::read_to_string(world.join(SETTINGS)).unwrap();
        for line in [
            "port = 30000\n",
            "name = peddn\n",
            "protector_radius = 8\n",
            "secure.http_mods = lep_bridge\n",
            "lep_bridge_url = http://127.0.0.1:8080\n",
            "lep_bridge_key = lepw_0123abcd\n",
        ] {
            assert!(settings.contains(line), "{line}");
        }
        // The settings hold a key.
        let mode = fs::metadata(world.join(SETTINGS))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600);
        // Game and mods come from the template of that version.
        assert_eq!(
            fs::read_link(world.join("games")).unwrap(),
            PathBuf::from("../../templates/bdbbf00c8a29/games")
        );
        assert_eq!(
            fs::read_link(world.join("mods")).unwrap(),
            PathBuf::from("../../templates/bdbbf00c8a29/mods")
        );
        assert_eq!(list(data.path()).unwrap(), [(id, note)]);
        // Nothing is left over next to it.
        assert_eq!(fs::read_dir(data.path().join("worlds")).unwrap().count(), 1);
    }

    #[test]
    fn a_world_that_is_there_keeps_port_and_map() {
        let data = tempfile::tempdir().unwrap();
        let manifest = manifest();
        let id = WorldId::parse(ID).unwrap();
        create(&id, &plan(data.path(), &manifest)).unwrap();
        let world = folder(data.path(), &id);
        fs::write(world.join("world/map.sqlite"), "the map").unwrap();

        // The same job again, with a new key and other ports.
        let mut again = plan(data.path(), &manifest);
        again.bridge_key = "lepw_new";
        again.ports = 31000..=31001;
        again.template = "ffffffffffff";
        let Created::Kept(note) = create(&id, &again).unwrap() else {
            panic!("the world was created again");
        };
        assert_eq!(note.port, 30000);
        assert_eq!(note.template, "bdbbf00c8a29");
        assert_eq!(
            fs::read_to_string(world.join("world/map.sqlite")).unwrap(),
            "the map"
        );
        let settings = fs::read_to_string(world.join(SETTINGS)).unwrap();
        assert!(settings.contains("lep_bridge_key = lepw_new\n"));
        assert!(settings.contains("port = 30000\n"));
        assert!(!settings.contains("lepw_0123abcd"));
    }

    #[test]
    fn every_world_gets_its_own_port_until_none_is_left() {
        let data = tempfile::tempdir().unwrap();
        let manifest = manifest();
        let ids = [
            ID,
            OTHER,
            "11111111-2222-4333-8444-555555555555",
            "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
        ];
        let mut ports = Vec::new();
        for text in &ids[..3] {
            let id = WorldId::parse(text).unwrap();
            match create(&id, &plan(data.path(), &manifest)).unwrap() {
                Created::New(note) => ports.push(note.port),
                Created::Kept(_) => panic!("the world was there"),
            }
        }
        assert_eq!(ports, [30000, 30001, 30002]);

        let id = WorldId::parse(ids[3]).unwrap();
        let refused = create(&id, &plan(data.path(), &manifest)).unwrap_err();
        assert!(format!("{refused:#}").contains("no port is free"));
        assert!(!folder(data.path(), &id).exists());
        assert_eq!(list(data.path()).unwrap().len(), 3);
        assert_eq!(states(data.path()).unwrap().len(), 3);
    }

    #[test]
    fn refuses_values_that_could_add_settings() {
        let data = tempfile::tempdir().unwrap();
        let manifest = manifest();
        let id = WorldId::parse(ID).unwrap();

        let mut wrong_key = plan(data.path(), &manifest);
        wrong_key.bridge_key = "lepw_x\nname = intruder";
        assert!(create(&id, &wrong_key).is_err());
        let mut other_key = plan(data.path(), &manifest);
        other_key.bridge_key = "lepa_0123";
        assert!(create(&id, &other_key).is_err());
        let mut wrong_admin = plan(data.path(), &manifest);
        wrong_admin.admin = "peddn\nlep_debug = true";
        assert!(create(&id, &wrong_admin).is_err());

        assert!(!folder(data.path(), &id).exists());
        assert!(list(data.path()).unwrap().is_empty());
    }

    #[test]
    fn lists_only_what_is_a_world() {
        let data = tempfile::tempdir().unwrap();
        assert!(list(data.path()).unwrap().is_empty());
        let worlds = data.path().join("worlds");
        fs::create_dir_all(worlds.join("not-a-world")).unwrap();
        fs::create_dir_all(worlds.join(OTHER)).unwrap();
        fs::create_dir_all(worlds.join(format!(".creating-{ID}"))).unwrap();
        assert!(list(data.path()).unwrap().is_empty());

        // A folder that carries the name of a world but is none is not
        // overwritten.
        let manifest = manifest();
        let id = WorldId::parse(OTHER).unwrap();
        assert!(create(&id, &plan(data.path(), &manifest)).is_err());
    }
}

//! The template this agent was built with. These tests only exist in a
//! build that embeds one: scripts/template-build.sh, then cargo with
//! LEP_TEMPLATE pointing to the archive.
#![cfg(lep_template)]

use std::fs;
use std::path::Path;

use lep_agent::template::{self, Outcome, FILE_LIST, MANIFEST};

fn folders(path: &Path) -> Vec<String> {
    let mut names: Vec<String> = fs::read_dir(path)
        .unwrap()
        .map(|entry| entry.unwrap())
        .filter(|entry| entry.path().is_dir())
        .map(|entry| entry.file_name().into_string().unwrap())
        .collect();
    names.sort();
    names
}

#[test]
fn the_embedded_template_holds_what_a_world_needs() {
    let embedded = template::embedded().expect("built with a template");
    let data = tempfile::tempdir().unwrap();
    let (folder, outcome) = template::ensure(data.path(), embedded).unwrap();
    assert_eq!(outcome, Outcome::Unpacked);
    assert_eq!(embedded.version.len(), 12);

    // The game, our mods as one modpack, and the third-party mods.
    assert!(folder.join("games/minetest_game/game.conf").is_file());
    assert!(folder.join("mods/lep/modpack.conf").is_file());
    assert!(folder.join("mods/lep/lep_core/init.lua").is_file());
    assert!(folder.join("mods/lep/lep_bridge/init.lua").is_file());

    let manifest: toml::Table = fs::read_to_string(folder.join(MANIFEST))
        .unwrap()
        .parse()
        .unwrap();
    assert_eq!(manifest["game"]["commit"].as_str().unwrap().len(), 40);
    let mods = manifest["mods"].as_array().unwrap();
    assert!(!mods.is_empty());
    let mut expected = vec!["lep".to_owned()];
    for entry in mods {
        let name = entry["name"].as_str().unwrap();
        assert_eq!(entry["commit"].as_str().unwrap().len(), 40);
        assert!(folder.join("mods").join(name).join("mod.conf").is_file());
        expected.push(name.to_owned());
    }
    expected.sort();
    assert_eq!(folders(&folder.join("mods")), expected);

    // Every mod of ours that the manifest names is there.
    for name in manifest["lep_mods"].as_array().unwrap() {
        let name = name.as_str().unwrap();
        assert!(folder
            .join("mods/lep")
            .join(name)
            .join("init.lua")
            .is_file());
    }

    // The licence texts travel with it.
    assert!(folder.join("licenses/LICENSE.md").is_file());
    assert!(folder
        .join("licenses/LICENSES/AGPL-3.0-or-later.txt")
        .is_file());
    assert!(folder.join("games/minetest_game/LICENSE.txt").is_file());

    // No tests, no history, no links.
    let list = fs::read_to_string(folder.join(FILE_LIST)).unwrap();
    assert!(!list.contains("/spec/"));
    assert!(!list.contains("/.git/"));
}

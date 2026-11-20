//! Embeds the template for worlds, if the build is told where it is.
//!
//! The variable LEP_TEMPLATE names the archive that
//! scripts/template-build.sh made. scripts/agent-build.sh sets it. Without
//! it the agent is built without a template: it runs and reports, but
//! cannot create worlds. That is how plain `cargo build` and the tests
//! work, which need no network.

use std::env;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};

use flate2::read::GzDecoder;
use sha2::{Digest, Sha256};

/// File inside the archive that lists every other file with its
/// checksum. Its own checksum is the version of the template.
const FILE_LIST: &str = "files.sha256";

fn main() {
    println!("cargo::rustc-check-cfg=cfg(lep_template)");
    println!("cargo::rerun-if-env-changed=LEP_TEMPLATE");
    let Some(archive) = env::var_os("LEP_TEMPLATE").filter(|path| !path.is_empty()) else {
        return;
    };
    let archive = PathBuf::from(archive);
    println!("cargo::rerun-if-changed={}", archive.display());
    if !archive.is_file() {
        panic!(
            "LEP_TEMPLATE names {}, which is no file. scripts/template-build.sh makes it",
            archive.display()
        );
    }
    let version = version_of(&archive)
        .unwrap_or_else(|why| panic!("cannot use the template {}: {why}", archive.display()));
    let out = PathBuf::from(env::var("OUT_DIR").expect("set by cargo")).join("template.tar.gz");
    fs::copy(&archive, &out).expect("cannot copy the template");
    println!("cargo::rustc-env=LEP_TEMPLATE_VERSION={version}");
    println!("cargo::rustc-env=LEP_TEMPLATE_ARCHIVE={}", out.display());
    println!("cargo::rustc-cfg=lep_template");
}

/// Reads the list of files from the archive and returns the start of
/// its checksum.
fn version_of(archive: &Path) -> Result<String, String> {
    let file = fs::File::open(archive).map_err(|err| err.to_string())?;
    let mut tar = tar::Archive::new(GzDecoder::new(file));
    for entry in tar.entries().map_err(|err| err.to_string())? {
        let mut entry = entry.map_err(|err| err.to_string())?;
        let path = entry.path().map_err(|err| err.to_string())?.into_owned();
        if path.strip_prefix(".").unwrap_or(&path) == Path::new(FILE_LIST) {
            let mut list = Vec::new();
            entry
                .read_to_end(&mut list)
                .map_err(|err| err.to_string())?;
            return Ok(hex::encode(Sha256::digest(&list))[..12].to_owned());
        }
    }
    Err(format!("it holds no {FILE_LIST}"))
}

//! The services of the worlds. Every world is one service of systemd,
//! made from one template: `lep-world@<identifier>.service`. They are
//! services of the user the agent runs as, so the agent needs no rights
//! on the system.
//!
//! systemd remembers which worlds are to run: starting a world also
//! enables its service, stopping disables it. After a reboot systemd
//! brings the enabled ones up by itself.
//!
//! The only program the agent ever starts is `systemctl --user`, with
//! fixed arguments and the name of a service built from an identifier
//! that was checked. No shell is involved.

use std::collections::BTreeSet;
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{bail, Context, Result};

use crate::worlds::{self, WorldId};

/// Start of the name of every service of a world.
const PREFIX: &str = "lep-world@";
const SUFFIX: &str = ".service";
/// How long a world gets to show that it stays up after its start.
const SETTLE: std::time::Duration = std::time::Duration::from_secs(3);
/// Name of the file the services are made from.
pub const TEMPLATE_FILE: &str = "lep-world@.service";

/// What the agent can do with the services of the worlds.
pub trait Units: Send + Sync {
    /// Puts the template for the services in place. Returns true if it
    /// was new or changed.
    fn install(&self, template: &str) -> Result<bool>;
    /// Starts a world now and after every reboot.
    fn start(&self, id: &WorldId) -> Result<()>;
    /// Stops a world and keeps it stopped after a reboot.
    fn stop(&self, id: &WorldId) -> Result<()>;
    /// Starts a world anew if it runs. A stopped world stays stopped.
    fn restart(&self, id: &WorldId) -> Result<()>;
    /// Returns the worlds that run.
    fn running(&self) -> Result<BTreeSet<WorldId>>;
}

/// Returns the name of the service of a world.
pub fn service_name(id: &WorldId) -> String {
    format!("{PREFIX}{id}{SUFFIX}")
}

/// Returns the world a service belongs to, if it is one of a world.
fn world_of(service: &str) -> Option<WorldId> {
    let id = service.strip_prefix(PREFIX)?.strip_suffix(SUFFIX)?;
    WorldId::parse(id).ok()
}

/// Returns true if a path can stand in a service file as it is: nothing
/// in it that systemd would read as more than a path.
fn is_plain_path(path: &Path) -> bool {
    path.is_absolute()
        && path.to_str().is_some_and(|text| {
            text.chars()
                .all(|c| c.is_ascii_alphanumeric() || "/_.-".contains(c))
        })
}

/// Writes the template the services of the worlds are made from. `%i`
/// stands for the identifier of the world.
pub fn template(data_dir: &Path, luanti: &Path) -> Result<String> {
    if !is_plain_path(data_dir) || !is_plain_path(luanti) {
        bail!(
            "the folder of the agent and the path of Luanti may only hold letters, digits, \
             / _ . and -, so they can stand in the service of a world"
        );
    }
    let world = format!("{}/{}/%i", data_dir.display(), worlds::FOLDER);
    Ok(format!(
        "# Written by the LEP agent at every start. Changes are overwritten.\n\
         \n\
         [Unit]\n\
         Description=Luanti Education Platform: world %i\n\
         \n\
         [Service]\n\
         Environment=LUANTI_USER_PATH={world} MINETEST_USER_PATH={world}\n\
         # Only errors go to the journal. What happens in the game, chat\n\
         # included, stays in the log file of the world.\n\
         ExecStart={luanti} --quiet --config {world}/{settings} --world {world}/world\n\
         Restart=on-failure\n\
         RestartSec=10\n\
         TimeoutStopSec=60\n\
         \n\
         [Install]\n\
         WantedBy=default.target\n",
        luanti = luanti.display(),
        settings = worlds::SETTINGS,
    ))
}

/// The real thing: `systemctl --user`.
pub struct Systemctl {
    /// Folder for the services of the user, usually
    /// `~/.config/systemd/user`.
    folder: PathBuf,
}

impl Systemctl {
    /// Finds the folder for the services of the user the agent runs as.
    pub fn for_this_user() -> Result<Self> {
        let config = match std::env::var_os("XDG_CONFIG_HOME").filter(|path| !path.is_empty()) {
            Some(path) => PathBuf::from(path),
            None => PathBuf::from(
                std::env::var_os("HOME")
                    .filter(|path| !path.is_empty())
                    .context("the agent has no home folder to keep the services in")?,
            )
            .join(".config"),
        };
        Ok(Self {
            folder: config.join("systemd/user"),
        })
    }

    /// Runs `systemctl --user` with these arguments and returns what it
    /// printed.
    fn systemctl(&self, arguments: &[&str]) -> Result<String> {
        let mut command = Command::new("systemctl");
        command.arg("--user").args(arguments).stdin(Stdio::null());
        if let Some(folder) = missing_runtime_dir() {
            command.env("XDG_RUNTIME_DIR", folder);
        }
        let output = command.output().context("cannot run systemctl")?;
        if !output.status.success() {
            let said = String::from_utf8_lossy(&output.stderr);
            let said = said.lines().next().unwrap_or("no reason given").trim();
            bail!("systemctl {} failed: {said}", arguments[0]);
        }
        Ok(String::from_utf8_lossy(&output.stdout).into_owned())
    }
}

/// Where systemd keeps the way to the services of this user, if the
/// agent was not told. As a service the agent is told. Started by hand
/// for another user, as with `sudo -u lep-agent lep-agent check`, it is not,
/// and `systemctl --user` would not find the services.
fn missing_runtime_dir() -> Option<PathBuf> {
    if std::env::var_os("XDG_RUNTIME_DIR").is_some_and(|folder| !folder.is_empty()) {
        return None;
    }
    let user = fs::metadata("/proc/self").ok()?.uid();
    let folder = PathBuf::from(format!("/run/user/{user}"));
    folder.is_dir().then_some(folder)
}

impl Units for Systemctl {
    fn install(&self, template: &str) -> Result<bool> {
        let path = self.folder.join(TEMPLATE_FILE);
        if fs::read_to_string(&path).is_ok_and(|there| there == template) {
            return Ok(false);
        }
        fs::create_dir_all(&self.folder)
            .with_context(|| format!("cannot create {}", self.folder.display()))?;
        let fresh = self.folder.join(format!(".{TEMPLATE_FILE}.new"));
        fs::write(&fresh, template)
            .and_then(|()| fs::rename(&fresh, &path))
            .with_context(|| format!("cannot write {}", path.display()))?;
        self.systemctl(&["daemon-reload"])?;
        Ok(true)
    }

    fn start(&self, id: &WorldId) -> Result<()> {
        let service = service_name(id);
        self.systemctl(&["enable", "--now", &service])?;
        // systemd is content once the program was started. A world that
        // cannot run ends right away, so look again a moment later.
        std::thread::sleep(SETTLE);
        if self.systemctl(&["is-active", &service]).is_err() {
            bail!(
                "the world was started, but ended at once. Why is in its journal: \
                 journalctl _SYSTEMD_USER_UNIT={service}"
            );
        }
        Ok(())
    }

    fn stop(&self, id: &WorldId) -> Result<()> {
        self.systemctl(&["disable", "--now", &service_name(id)])?;
        Ok(())
    }

    fn restart(&self, id: &WorldId) -> Result<()> {
        self.systemctl(&["try-restart", &service_name(id)])?;
        Ok(())
    }

    fn running(&self) -> Result<BTreeSet<WorldId>> {
        let pattern = format!("{PREFIX}*{SUFFIX}");
        let listed = self.systemctl(&[
            "list-units",
            "--type=service",
            "--state=active",
            "--plain",
            "--no-legend",
            &pattern,
        ])?;
        Ok(parse_running(&listed))
    }
}

/// Reads the worlds out of what `systemctl list-units` printed: one
/// service per line, its name first.
fn parse_running(listed: &str) -> BTreeSet<WorldId> {
    listed
        .lines()
        .filter_map(|line| line.split_whitespace().next())
        .filter_map(world_of)
        .collect()
}

/// Services that only exist in memory, for tests.
pub mod testing {
    use super::*;
    use std::sync::Mutex;

    /// Remembers what was asked of it. `broken` makes every call fail,
    /// like a machine without systemd.
    #[derive(Default)]
    pub struct FakeUnits {
        pub running: Mutex<BTreeSet<WorldId>>,
        pub template: Mutex<Option<String>>,
        pub calls: Mutex<Vec<String>>,
        pub broken: bool,
        /// How many times `install` fails before it works, like right
        /// after a boot.
        pub install_failures: Mutex<u32>,
    }

    impl FakeUnits {
        pub fn broken() -> Self {
            Self {
                broken: true,
                ..Self::default()
            }
        }

        fn note(&self, call: String) -> Result<()> {
            if self.broken {
                bail!("systemctl failed: no systemd here");
            }
            self.calls.lock().unwrap().push(call);
            Ok(())
        }

        pub fn calls(&self) -> Vec<String> {
            self.calls.lock().unwrap().clone()
        }
    }

    impl Units for FakeUnits {
        fn install(&self, template: &str) -> Result<bool> {
            {
                let mut failures = self.install_failures.lock().unwrap();
                if *failures > 0 {
                    *failures -= 1;
                    bail!("systemctl daemon-reload failed: not ready yet");
                }
            }
            self.note("install".to_owned())?;
            let mut there = self.template.lock().unwrap();
            let changed = there.as_deref() != Some(template);
            *there = Some(template.to_owned());
            Ok(changed)
        }

        fn start(&self, id: &WorldId) -> Result<()> {
            self.note(format!("start {id}"))?;
            self.running.lock().unwrap().insert(id.clone());
            Ok(())
        }

        fn stop(&self, id: &WorldId) -> Result<()> {
            self.note(format!("stop {id}"))?;
            self.running.lock().unwrap().remove(id);
            Ok(())
        }

        fn restart(&self, id: &WorldId) -> Result<()> {
            self.note(format!("restart {id}"))
        }

        fn running(&self) -> Result<BTreeSet<WorldId>> {
            if self.broken {
                bail!("systemctl failed: no systemd here");
            }
            Ok(self.running.lock().unwrap().clone())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ID: &str = "0b54f9c6-5f0e-4a3c-9d2e-7a1c0f3b8e21";

    #[test]
    fn names_the_service_of_a_world() {
        let id = WorldId::parse(ID).unwrap();
        let name = service_name(&id);
        assert_eq!(name, format!("lep-world@{ID}.service"));
        assert_eq!(world_of(&name), Some(id));
        for other in [
            "lep-agent.service",
            "lep-world@.service",
            "lep-world@7b.service",
            "lep-world@../../x.service",
        ] {
            assert_eq!(world_of(other), None, "{other}");
        }
    }

    #[test]
    fn writes_the_template_from_the_settings() {
        let text = template(
            Path::new("/var/lib/lep-agent"),
            Path::new("/usr/local/bin/luantiserver"),
        )
        .unwrap();
        assert!(text.contains(
            "ExecStart=/usr/local/bin/luantiserver --quiet \
             --config /var/lib/lep-agent/worlds/%i/minetest.conf --world /var/lib/lep-agent/worlds/%i/world\n"
        ));
        assert!(text.contains("Environment=LUANTI_USER_PATH=/var/lib/lep-agent/worlds/%i "));
        assert!(text.contains("Restart=on-failure\n"));
        assert!(text.contains("WantedBy=default.target\n"));
    }

    #[test]
    fn refuses_paths_that_systemd_would_read_differently() {
        let luanti = Path::new("/usr/local/bin/luantiserver");
        for folder in [
            "/var/lib/my lep",
            "relative/lep",
            "/var/lib/lep-agent%i",
            "/var/lib/lep-agent\nExecStartPre=/bin/x",
            "/var/lib/lep-agent;x",
            "/var/lib/$HOME",
        ] {
            assert!(template(Path::new(folder), luanti).is_err(), "{folder}");
        }
        assert!(template(
            Path::new("/var/lib/lep-agent"),
            Path::new("luantiserver --x")
        )
        .is_err());
    }

    #[test]
    fn reads_which_worlds_run() {
        let listed = format!(
            "lep-world@{ID}.service loaded active running Luanti Education Platform: world {ID}\n\
             lep-world@not-a-world.service loaded active running something else\n\
             lep-agent.service loaded active running agent\n\n"
        );
        let running = parse_running(&listed);
        assert_eq!(running.len(), 1);
        assert!(running.contains(&WorldId::parse(ID).unwrap()));
        assert!(parse_running("").is_empty());
    }

    #[test]
    fn installs_the_template_only_when_it_changes() {
        let folder = tempfile::tempdir().unwrap();
        let units = Systemctl {
            folder: folder.path().join("systemd/user"),
        };
        let path = folder.path().join("systemd/user").join(TEMPLATE_FILE);
        // The same text is there already: nothing to do, and systemd is
        // not asked.
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(&path, "the template").unwrap();
        assert!(!units.install("the template").unwrap());
    }
}

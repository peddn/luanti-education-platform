//! Settings of the agent. They come from one file, by default
//! `/etc/lep/agent.toml`, which only the user of the agent may read: it
//! holds the key.

use std::fmt;
use std::fs;
use std::net::IpAddr;
use std::ops::RangeInclusive;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};
use reqwest::Url;
use serde::Deserialize;

/// Where the settings are, if nothing else is said.
pub const DEFAULT_PATH: &str = "/etc/lep/agent.toml";
/// Folder that holds everything the agent touches, if nothing else is
/// said.
pub const DEFAULT_DATA_DIR: &str = "/var/lib/lep-agent";
/// The Luanti server the worlds run with, if nothing else is said. It
/// is where scripts/luanti-build.sh installs it.
pub const DEFAULT_LUANTI: &str = "/usr/local/bin/luantiserver";
/// Ports the worlds get, if nothing else is said.
pub const DEFAULT_PORTS: RangeInclusive<u16> = 30000..=30099;
/// Start of every key of an agent.
const KEY_PREFIX: &str = "lepa_";

/// The settings as they stand in the file. A name the agent does not
/// know is an error, so a typing mistake does not go unnoticed.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct File {
    backend: String,
    key: String,
    data_dir: Option<PathBuf>,
    admin: Option<String>,
    ports: Option<String>,
    luanti: Option<PathBuf>,
    host: Option<String>,
}

/// The checked settings.
#[derive(Clone, PartialEq, Eq)]
pub struct Config {
    /// Address of the backend, ending with a slash.
    pub backend: Url,
    /// Key the agent calls with.
    pub key: String,
    /// Folder that holds everything the agent touches.
    pub data_dir: PathBuf,
    /// Account name of the server admin, entered into every new world.
    /// Without it the agent creates no worlds.
    pub admin: Option<String>,
    /// Ports the worlds get, first and last.
    pub ports: RangeInclusive<u16>,
    /// The Luanti server the worlds run with.
    pub luanti: PathBuf,
    /// Name under which players reach this machine. With the port of a
    /// world it makes the address on the access slips.
    pub host: Option<String>,
}

/// The key never gets into a log, not even by accident.
impl fmt::Debug for Config {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Config")
            .field("backend", &self.backend.as_str())
            .field("key", &"(hidden)")
            .field("data_dir", &self.data_dir)
            .field("admin", &self.admin)
            .field("ports", &self.ports)
            .field("luanti", &self.luanti)
            .field("host", &self.host)
            .finish()
    }
}

impl Config {
    /// Reads and checks the settings from a file.
    pub fn read(path: &Path) -> Result<Self> {
        let text = fs::read_to_string(path)
            .with_context(|| format!("cannot read the settings in {}", path.display()))?;
        Self::parse(&text).with_context(|| format!("the settings in {} are wrong", path.display()))
    }

    /// Checks settings given as text.
    pub fn parse(text: &str) -> Result<Self> {
        // The message of the parser can quote the line it stumbled over,
        // and that line may be the key. So only the place is passed on.
        let file: File = toml::from_str(text).map_err(|err| {
            let place = err
                .span()
                .map(|span| text[..span.start.min(text.len())].lines().count().max(1));
            let what = unquoted(err.message());
            match place {
                Some(line) => anyhow::anyhow!("line {line}: {what}"),
                None => anyhow::anyhow!("{what}"),
            }
        })?;

        let backend = check_backend(&file.backend)?;
        let key = file.key.trim().to_owned();
        if !key.starts_with(KEY_PREFIX) || key.chars().any(|c| !c.is_ascii_graphic()) {
            bail!(
                "'key' is not a key of an agent. The backend makes one with: lep-backend agent key"
            );
        }
        let data_dir = file
            .data_dir
            .unwrap_or_else(|| PathBuf::from(DEFAULT_DATA_DIR));
        if !data_dir.is_absolute() {
            bail!("'data_dir' must be a full path that starts with /");
        }
        let admin = file.admin.map(|name| name.trim().to_owned());
        if admin.as_deref().is_some_and(|name| !is_account_name(name)) {
            bail!("'admin' is no account name: 1 to 19 characters, only letters, digits, - and _");
        }
        let ports = match file.ports.as_deref() {
            Some(text) => parse_ports(text)?,
            None => DEFAULT_PORTS,
        };
        let luanti = file.luanti.unwrap_or_else(|| PathBuf::from(DEFAULT_LUANTI));
        if !luanti.is_absolute() {
            bail!("'luanti' must be a full path that starts with /");
        }
        let host = file.host.map(|host| host.trim().to_owned());
        if host.as_deref().is_some_and(|host| !is_host(host)) {
            bail!(
                "'host' must be the name or address players reach this machine under, like \
                 spiel.schule.example, without a port"
            );
        }
        Ok(Self {
            backend,
            key,
            data_dir,
            admin,
            ports,
            luanti,
            host,
        })
    }
}

/// Returns true if a text can be the name of an account in a world.
pub fn is_account_name(name: &str) -> bool {
    (1..=19).contains(&name.len())
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

/// Returns true if a text can be the name or address of a machine.
fn is_host(text: &str) -> bool {
    (1..=100).contains(&text.len())
        && text
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || ".-:[]".contains(c))
}

/// Reads a range of ports like `30000-30099`.
fn parse_ports(text: &str) -> Result<RangeInclusive<u16>> {
    let wrong = || anyhow::anyhow!("'ports' must be a range like 30000-30099, above 1023");
    let (first, last) = text.split_once('-').ok_or_else(wrong)?;
    let first: u16 = first.trim().parse().map_err(|_| wrong())?;
    let last: u16 = last.trim().parse().map_err(|_| wrong())?;
    if first < 1024 || last < first {
        return Err(wrong());
    }
    Ok(first..=last)
}

/// Keeps a message of the parser only if it quotes nothing from the
/// file.
fn unquoted(message: &str) -> &str {
    if message.contains(KEY_PREFIX) {
        "cannot be read"
    } else {
        message
    }
}

/// Checks the address of the backend. The key travels with every
/// request, so the way must be closed to listeners: https, or the same
/// machine.
fn check_backend(text: &str) -> Result<Url> {
    let mut text = text.trim().to_owned();
    if !text.ends_with('/') {
        // Paths are joined to the address, which needs the slash.
        text.push('/');
    }
    let url = Url::parse(&text).context("'backend' is not an address")?;
    if url.query().is_some() || url.fragment().is_some() || !url.username().is_empty() {
        bail!("'backend' must be a plain address like https://lep.schule.example");
    }
    let Some(host) = url.host_str() else {
        bail!("'backend' names no machine");
    };
    let address = host.trim_start_matches('[').trim_end_matches(']');
    let local = host == "localhost"
        || address
            .parse::<IpAddr>()
            .is_ok_and(|address| address.is_loopback());
    match url.scheme() {
        "https" => {}
        "http" if local => {}
        "http" => bail!(
            "'backend' must start with https://, because the key travels with every request. \
             Only a backend on the same machine may be reached with http://"
        ),
        _ => bail!("'backend' must start with https://"),
    }
    Ok(url)
}

/// Returns true if others than the owner can read the file.
pub fn is_open_to_others(path: &Path) -> bool {
    fs::metadata(path)
        .map(|meta| meta.permissions().mode() & 0o077 != 0)
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    const KEY: &str = "lepa_0123456789abcdef";

    fn settings(backend: &str) -> String {
        format!("backend = \"{backend}\"\nkey = \"{KEY}\"\n")
    }

    #[test]
    fn reads_the_settings() {
        let config = Config::parse(
            "backend = \"https://lep.schule.example\"\nkey = \"lepa_0123456789abcdef\"\n\
             data_dir = \"/srv/lep\"\n",
        )
        .unwrap();
        assert_eq!(config.backend.as_str(), "https://lep.schule.example/");
        assert_eq!(config.key, KEY);
        assert_eq!(config.data_dir, PathBuf::from("/srv/lep"));
    }

    #[test]
    fn reads_admin_and_ports() {
        let base = settings("https://lep.schule.example");
        let config = Config::parse(&base).unwrap();
        assert_eq!(config.admin, None);
        assert_eq!(config.ports, DEFAULT_PORTS);
        assert_eq!(config.luanti, PathBuf::from(DEFAULT_LUANTI));
        let other = format!("{base}luanti = \"/opt/luanti/bin/luantiserver\"\n");
        assert_eq!(
            Config::parse(&other).unwrap().luanti,
            PathBuf::from("/opt/luanti/bin/luantiserver")
        );
        assert!(Config::parse(&format!("{base}luanti = \"luantiserver\"\n")).is_err());

        assert_eq!(config.host, None);
        for host in ["spiel.schule.example", "192.0.2.10", "[2001:db8::1]"] {
            let text = format!("{base}host = \"{host}\"\n");
            assert_eq!(Config::parse(&text).unwrap().host.as_deref(), Some(host));
        }
        for host in ["", "spiel schule", "spiel.schule.example, Port 1", "a/b"] {
            let text = format!("{base}host = \"{host}\"\n");
            assert!(Config::parse(&text).is_err(), "{host}");
        }

        let config = Config::parse(&format!(
            "{base}admin = \"peddn\"\nports = \"31000-31009\"\n"
        ))
        .unwrap();
        assert_eq!(config.admin.as_deref(), Some("peddn"));
        assert_eq!(config.ports, 31000..=31009);

        for admin in ["", "with space", "a\\nname = x", "much_too_long_for_a_name"] {
            let text = format!("{base}admin = \"{admin}\"\n");
            assert!(Config::parse(&text).is_err(), "{admin}");
        }
        for ports in ["", "30000", "30010-30000", "80-90", "a-b", "30000-70000"] {
            let text = format!("{base}ports = \"{ports}\"\n");
            assert!(Config::parse(&text).is_err(), "{ports}");
        }
    }

    #[test]
    fn the_folder_has_a_default() {
        let config = Config::parse(&settings("https://lep.schule.example/")).unwrap();
        assert_eq!(config.data_dir, PathBuf::from(DEFAULT_DATA_DIR));
    }

    #[test]
    fn keeps_a_path_in_the_address() {
        let config = Config::parse(&settings("https://schule.example/lep")).unwrap();
        assert_eq!(
            config.backend.join("api/agent/v1/report").unwrap().as_str(),
            "https://schule.example/lep/api/agent/v1/report"
        );
    }

    #[test]
    fn the_key_only_travels_protected() {
        for local in [
            "http://127.0.0.1:8080",
            "http://localhost:8080",
            "http://[::1]:8080",
        ] {
            assert!(Config::parse(&settings(local)).is_ok(), "{local}");
        }
        for open in [
            "http://lep.schule.example",
            "http://192.168.1.5:8080",
            "http://localhost.example",
            "ftp://lep.schule.example",
            "lep.schule.example",
            "https://user:secret@lep.schule.example",
            "https://lep.schule.example/?x=1",
        ] {
            assert!(Config::parse(&settings(open)).is_err(), "{open}");
        }
    }

    #[test]
    fn refuses_what_is_no_key_of_an_agent() {
        for key in ["", "lepw_0123", "something", "lepa_01 23"] {
            let text = format!("backend = \"https://lep.schule.example\"\nkey = \"{key}\"\n");
            assert!(Config::parse(&text).is_err(), "{key}");
        }
    }

    #[test]
    fn refuses_unknown_names_and_relative_folders() {
        let unknown = format!("{}bakend = \"x\"\n", settings("https://lep.schule.example"));
        assert!(Config::parse(&unknown).is_err());
        let relative = format!(
            "{}data_dir = \"worlds\"\n",
            settings("https://lep.schule.example")
        );
        assert!(Config::parse(&relative).is_err());
        assert!(Config::parse("backend = \"https://lep.schule.example\"\n").is_err());
    }

    #[test]
    fn the_key_shows_up_in_no_message() {
        let config = Config::parse(&settings("https://lep.schule.example")).unwrap();
        assert!(!format!("{config:?}").contains(KEY));

        // A line that cannot be read is named by its number, not quoted.
        let broken = format!("backend = \"https://lep.schule.example\"\nkey = {KEY}\n");
        let message = format!("{:#}", Config::parse(&broken).unwrap_err());
        assert!(!message.contains(KEY), "{message}");
        assert!(message.contains("line 2"), "{message}");

        let wrong = format!("backend = \"http://lep.schule.example\"\nkey = \"{KEY}\"\n");
        let message = format!("{:#}", Config::parse(&wrong).unwrap_err());
        assert!(!message.contains(KEY), "{message}");
    }

    #[test]
    fn notices_a_file_others_can_read() {
        let folder = tempfile::tempdir().unwrap();
        let path = folder.path().join("agent.toml");
        fs::write(&path, settings("https://lep.schule.example")).unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o644)).unwrap();
        assert!(is_open_to_others(&path));
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();
        assert!(!is_open_to_others(&path));
        assert_eq!(Config::read(&path).unwrap().key, KEY);
        assert!(Config::read(&folder.path().join("missing.toml")).is_err());
    }
}

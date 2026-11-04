//! Lattice Phase 4 **Port** dial contract.
//!
//! The in-cluster homeserver is the wasmCloud component `matrix-cs`. Lavoisier stays the
//! Matrix client (this gateway), dialling that component's HTTP host interface. This is not a
//! second gateway and not a wasm guest.
//!
//! The dial address and the HTTP `Host` header are different strings. Kubernetes resolves
//! `matrix-cs.wasmcloud.svc.cluster.local`; the component's `hostInterfaces` host is
//! `matrix-cs.wasmcloud.svc`. User ids on that plane are `@localpart:davidlee18.dev`.

use std::path::Path;

use lvz_protocol::GatewayError;

/// ClusterIP dial URL. `Host` is [`LATTICE_HTTP_HOST`], not this authority.
pub const LATTICE_HOMESERVER: &str = "http://matrix-cs.wasmcloud.svc.cluster.local:80";

/// `hostInterfaces` host from `components/matrix-cs/wadm.yaml`. Sent as the HTTP `Host` header.
pub const LATTICE_HTTP_HOST: &str = "matrix-cs.wasmcloud.svc";

/// Matrix server name for lattice user ids (`@localpart:davidlee18.dev`).
pub const LATTICE_SERVER_NAME: &str = "davidlee18.dev";

/// ECS Elastic File System the lattice workload must not mount. The spider42 task may still
/// use it; a lattice state directory that names this id is rejected.
pub const ECS_EFS_VOLUME_ID: &str = "fs-0966896c7d24d7b20";

/// ECS homeserver. A lattice dial must not reuse it.
pub const ECS_HOMESERVER_HOST: &str = "matrix.spider42.com";

/// Inputs the lattice rules look at. Secrets are not stored here; only whether one was set.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DialContract {
    /// Base URL, no trailing slash.
    pub homeserver: String,
    /// HTTP `Host` override. `None` means the URL authority (the ECS path).
    pub http_host: Option<String>,
    /// Expected `@localpart:server` server name. `None` means do not check.
    pub server_name: Option<String>,
    /// Login user: localpart or full MXID. Empty when authenticating with an access token only.
    pub user: String,
    /// Pinned device id.
    pub device_id: Option<String>,
    /// Session directory, if any. Ephemeral directories are allowed.
    pub state_dir: Option<String>,
    /// An access token was supplied.
    pub has_access_token: bool,
    /// A password was supplied.
    pub has_password: bool,
}

impl DialContract {
    /// The Phase 4 Port dial, with identity holes left empty for the caller to fill.
    ///
    /// Device id, user, and secrets are deployment inputs. This value is the homeserver half
    /// of the contract: URL, `Host`, and server name.
    pub fn phase4_dial() -> Self {
        Self {
            homeserver: LATTICE_HOMESERVER.to_string(),
            http_host: Some(LATTICE_HTTP_HOST.to_string()),
            server_name: Some(LATTICE_SERVER_NAME.to_string()),
            user: String::new(),
            device_id: None,
            state_dir: None,
            has_access_token: false,
            has_password: false,
        }
    }

    /// Whether these fields opt into the lattice plane (any one marker is enough to require
    /// the full pin, so a half-configured lattice dial fails instead of talking to spider42).
    pub fn is_lattice(&self) -> bool {
        homeserver_is_lattice(&self.homeserver)
            || self.http_host.as_deref() == Some(LATTICE_HTTP_HOST)
            || self.server_name.as_deref() == Some(LATTICE_SERVER_NAME)
    }

    /// Syntax checks always. Lattice completeness only when [`Self::is_lattice`] is set.
    pub fn validate(&self) -> Result<(), GatewayError> {
        if !self.homeserver.is_empty() {
            parse_http_base(&self.homeserver)?;
        }
        if let Some(host) = &self.http_host {
            check_http_host(host)?;
        }
        if let Some(name) = &self.server_name {
            check_server_name(name)?;
        }
        if self.is_lattice() {
            self.validate_lattice()?;
        }
        Ok(())
    }

    fn validate_lattice(&self) -> Result<(), GatewayError> {
        if !homeserver_is_lattice(&self.homeserver) {
            return Err(GatewayError::Bind(format!(
                "lattice MATRIX_HOMESERVER must be {LATTICE_HOMESERVER}"
            )));
        }
        if self.http_host.as_deref() != Some(LATTICE_HTTP_HOST) {
            return Err(GatewayError::Bind(format!(
                "lattice MATRIX_HTTP_HOST must be {LATTICE_HTTP_HOST}"
            )));
        }
        if self.server_name.as_deref() != Some(LATTICE_SERVER_NAME) {
            return Err(GatewayError::Bind(format!(
                "lattice MATRIX_SERVER_NAME must be {LATTICE_SERVER_NAME}"
            )));
        }
        if self
            .homeserver
            .to_ascii_lowercase()
            .contains(ECS_HOMESERVER_HOST)
        {
            return Err(GatewayError::Bind(format!(
                "lattice dial must not use the ECS homeserver {ECS_HOMESERVER_HOST}"
            )));
        }
        if self.device_id.as_deref().unwrap_or("").is_empty() {
            return Err(GatewayError::Bind(
                "lattice dial requires MATRIX_DEVICE_ID so the device id stays stable \
                 without the ECS volume"
                    .into(),
            ));
        }
        if let Some(dir) = &self.state_dir {
            if dir.contains(ECS_EFS_VOLUME_ID) {
                return Err(GatewayError::Bind(format!(
                    "lattice MATRIX_STATE_DIR must not use ECS volume {ECS_EFS_VOLUME_ID}"
                )));
            }
        }
        if let Some(server) = mxid_server(&self.user) {
            if !server.eq_ignore_ascii_case(LATTICE_SERVER_NAME) {
                return Err(GatewayError::Bind(format!(
                    "lattice user {user} is @{server}, not @{LATTICE_SERVER_NAME}",
                    user = self.user,
                    server = server,
                )));
            }
        }
        if !self.has_access_token && !self.has_password {
            return Err(GatewayError::Bind(
                "lattice dial needs MATRIX_ACCESS_TOKEN or MATRIX_PASSWORD".into(),
            ));
        }
        Ok(())
    }
}

/// `http://matrix-cs.wasmcloud.svc.cluster.local` with port 80 or omitted.
pub fn homeserver_is_lattice(homeserver: &str) -> bool {
    let Ok(base) = parse_http_base(homeserver) else {
        return false;
    };
    base.scheme == "http"
        && base
            .host
            .eq_ignore_ascii_case("matrix-cs.wasmcloud.svc.cluster.local")
        && base.port == 80
}

/// Host and port of the dial URL (the address to resolve, before the `Host` rewrite).
pub fn dial_host_port(homeserver: &str) -> Result<(String, u16), GatewayError> {
    let base = parse_http_base(homeserver)?;
    Ok((base.host, base.port))
}

/// Authority used on the wire. When `http_host` is set, the URL host becomes that name
/// (default ports omitted) so the `Host` header matches `hostInterfaces`.
pub fn request_base(homeserver: &str, http_host: Option<&str>) -> Result<String, GatewayError> {
    let Some(host) = http_host else {
        return Ok(homeserver.trim_end_matches('/').to_string());
    };
    check_http_host(host)?;
    let base = parse_http_base(homeserver)?;
    let default_port = if base.scheme == "https" { 443 } else { 80 };
    if base.port == default_port {
        Ok(format!("{}://{host}", base.scheme))
    } else {
        Ok(format!("{}://{host}:{}", base.scheme, base.port))
    }
}

/// Server name of an MXID (`@localpart:server`), if `user` is one.
pub fn mxid_server(user: &str) -> Option<&str> {
    let rest = user.strip_prefix('@')?;
    let (_, server) = rest.split_once(':')?;
    (!server.is_empty()).then_some(server)
}

/// Localpart for `POST /register`. Accepts `lav` or `@lav:davidlee18.dev`.
pub fn register_localpart(user: &str) -> &str {
    let bare = user.strip_prefix('@').unwrap_or(user);
    bare.split_once(':').map(|(local, _)| local).unwrap_or(bare)
}

/// Compare a resolved MXID with the configured server name.
pub fn user_on_server(user_id: &str, server_name: &str) -> Result<(), GatewayError> {
    match mxid_server(user_id) {
        Some(got) if got.eq_ignore_ascii_case(server_name) => Ok(()),
        Some(got) => Err(GatewayError::Bind(format!(
            "matrix user {user_id} is on {got}, not {server_name}"
        ))),
        None => Err(GatewayError::Bind(format!(
            "matrix user id {user_id} is not @localpart:server"
        ))),
    }
}

/// `MATRIX_HTTP_HOST`: a hostname, no scheme and no port.
pub fn check_http_host(host: &str) -> Result<(), GatewayError> {
    if host.is_empty()
        || host
            .chars()
            .any(|c| c.is_whitespace() || matches!(c, '/' | ':' | '@'))
        || host.contains("://")
    {
        return Err(GatewayError::Bind(format!(
            "MATRIX_HTTP_HOST must be a hostname without a scheme or port, got {host:?}"
        )));
    }
    Ok(())
}

/// `MATRIX_SERVER_NAME`: a Matrix server name, no user sigil and no port.
pub fn check_server_name(name: &str) -> Result<(), GatewayError> {
    if name.is_empty()
        || name
            .chars()
            .any(|c| c.is_whitespace() || matches!(c, '/' | '@' | ':'))
    {
        return Err(GatewayError::Bind(format!(
            "MATRIX_SERVER_NAME must be a Matrix server name, got {name:?}"
        )));
    }
    Ok(())
}

/// True when a state-dir path names the ECS volume. Lattice rejects that path; ECS does not.
pub fn state_dir_uses_ecs_efs(dir: &Path) -> bool {
    dir.to_string_lossy().contains(ECS_EFS_VOLUME_ID)
}

struct HttpBase {
    scheme: &'static str,
    host: String,
    port: u16,
}

fn parse_http_base(raw: &str) -> Result<HttpBase, GatewayError> {
    let raw = raw.trim().trim_end_matches('/');
    let (scheme, rest) = raw.split_once("://").ok_or_else(|| {
        GatewayError::Bind(format!(
            "MATRIX_HOMESERVER must be an http(s) URL, got {raw:?}"
        ))
    })?;
    let scheme = match scheme {
        "http" => "http",
        "https" => "https",
        _ => {
            return Err(GatewayError::Bind(format!(
                "MATRIX_HOMESERVER scheme must be http or https, got {scheme:?}"
            )))
        }
    };
    let authority = rest.split_once('/').map(|(a, _)| a).unwrap_or(rest);
    let authority = authority
        .rsplit_once('@')
        .map(|(_, host)| host)
        .unwrap_or(authority);
    if authority.is_empty() {
        return Err(GatewayError::Bind(
            "MATRIX_HOMESERVER is missing a host".into(),
        ));
    }
    let default_port: u16 = if scheme == "https" { 443 } else { 80 };
    let (host, port) = if let Some(rest) = authority.strip_prefix('[') {
        let (host, tail) = rest.split_once(']').ok_or_else(|| {
            GatewayError::Bind(format!("MATRIX_HOMESERVER has a bad IPv6 host: {raw:?}"))
        })?;
        let port = parse_port(tail, default_port)?;
        (host.to_string(), port)
    } else if let Some((host, port)) = authority.rsplit_once(':') {
        if !port.is_empty() && port.chars().all(|c| c.is_ascii_digit()) {
            (
                host.to_string(),
                parse_port(&format!(":{port}"), default_port)?,
            )
        } else {
            (authority.to_string(), default_port)
        }
    } else {
        (authority.to_string(), default_port)
    };
    if host.is_empty() {
        return Err(GatewayError::Bind(
            "MATRIX_HOMESERVER is missing a host".into(),
        ));
    }
    Ok(HttpBase { scheme, host, port })
}

fn parse_port(tail: &str, default_port: u16) -> Result<u16, GatewayError> {
    if tail.is_empty() {
        return Ok(default_port);
    }
    let Some(port) = tail.strip_prefix(':') else {
        return Err(GatewayError::Bind(format!(
            "MATRIX_HOMESERVER has a bad port in {tail:?}"
        )));
    };
    if port.is_empty() {
        return Ok(default_port);
    }
    port.parse::<u16>()
        .map_err(|_| GatewayError::Bind(format!("MATRIX_HOMESERVER has a bad port {port:?}")))
}

/// `MATRIX_REGISTER` parser. Empty is absent. Anything else must be a known boolean.
pub fn parse_register_flag(value: &str) -> Result<Option<bool>, GatewayError> {
    match value.trim().to_ascii_lowercase().as_str() {
        "" => Ok(None),
        "1" | "true" | "yes" | "on" => Ok(Some(true)),
        "0" | "false" | "no" | "off" => Ok(Some(false)),
        other => Err(GatewayError::Bind(format!(
            "MATRIX_REGISTER must be true or false, got {other:?}"
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lattice_ready() -> DialContract {
        DialContract {
            user: "@lav:davidlee18.dev".into(),
            device_id: Some("LAVOISIER_LATTICE".into()),
            state_dir: Some("/var/lib/lavoisier/matrix".into()),
            has_password: true,
            ..DialContract::phase4_dial()
        }
    }

    #[test]
    fn phase4_dial_is_the_clusterip_not_spider42() {
        let dial = DialContract::phase4_dial();
        assert_eq!(dial.homeserver, LATTICE_HOMESERVER);
        assert_eq!(dial.http_host.as_deref(), Some(LATTICE_HTTP_HOST));
        assert_eq!(dial.server_name.as_deref(), Some(LATTICE_SERVER_NAME));
        assert!(dial.is_lattice());
        assert!(!dial.homeserver.contains(ECS_HOMESERVER_HOST));
        assert!(!dial.homeserver.contains("spider42"));
        assert_eq!(
            request_base(&dial.homeserver, dial.http_host.as_deref()).unwrap(),
            "http://matrix-cs.wasmcloud.svc"
        );
    }

    #[test]
    fn lattice_identity_accepts_token_device_and_ephemeral_dir() {
        let mut dial = lattice_ready();
        dial.has_password = false;
        dial.has_access_token = true;
        dial.state_dir = None;
        assert!(dial.validate().is_ok());
    }

    #[test]
    fn lattice_rejects_spider42_user_efs_and_missing_device() {
        let mut spider_user = lattice_ready();
        spider_user.user = "@lav:matrix.spider42.com".into();
        let err = spider_user.validate().unwrap_err().to_string();
        assert!(err.contains(LATTICE_SERVER_NAME), "{err}");
        assert!(err.contains("spider42"), "{err}");

        let mut efs = lattice_ready();
        efs.state_dir = Some(format!("/mnt/{ECS_EFS_VOLUME_ID}/matrix"));
        let err = efs.validate().unwrap_err().to_string();
        assert!(err.contains(ECS_EFS_VOLUME_ID), "{err}");

        let mut nodev = lattice_ready();
        nodev.device_id = None;
        assert!(nodev
            .validate()
            .unwrap_err()
            .to_string()
            .contains("MATRIX_DEVICE_ID"));
    }

    #[test]
    fn ecs_spider42_path_is_not_lattice_and_may_name_the_efs_volume() {
        let ecs = DialContract {
            homeserver: "https://matrix.spider42.com".into(),
            http_host: None,
            server_name: None,
            user: "@lav:matrix.spider42.com".into(),
            device_id: Some("EXISTING".into()),
            state_dir: Some(format!("/mnt/{ECS_EFS_VOLUME_ID}/matrix")),
            has_access_token: true,
            has_password: false,
        };
        assert!(!ecs.is_lattice());
        assert!(ecs.validate().is_ok());
        assert!(state_dir_uses_ecs_efs(Path::new(
            "/mnt/fs-0966896c7d24d7b20/matrix"
        )));
    }

    #[test]
    fn partial_lattice_marker_fails_closed() {
        let mut only_host = DialContract {
            homeserver: "https://matrix.spider42.com".into(),
            http_host: Some(LATTICE_HTTP_HOST.into()),
            server_name: None,
            user: "@lav:matrix.spider42.com".into(),
            device_id: None,
            state_dir: None,
            has_access_token: true,
            has_password: false,
        };
        assert!(only_host.is_lattice());
        assert!(only_host.validate().is_err());

        only_host.http_host = None;
        only_host.server_name = Some(LATTICE_SERVER_NAME.into());
        let err = only_host.validate().unwrap_err().to_string();
        assert!(err.contains(LATTICE_HOMESERVER), "{err}");
    }

    #[test]
    fn localpart_and_server_name_parse() {
        assert_eq!(register_localpart("@lav:davidlee18.dev"), "lav");
        assert_eq!(register_localpart("lav"), "lav");
        assert_eq!(mxid_server("@lav:davidlee18.dev"), Some("davidlee18.dev"));
        assert!(mxid_server("lav").is_none());
        assert!(user_on_server("@lav:davidlee18.dev", LATTICE_SERVER_NAME).is_ok());
        assert!(user_on_server("@lav:matrix.spider42.com", LATTICE_SERVER_NAME).is_err());
    }

    #[test]
    fn register_flag_rejects_typos() {
        assert_eq!(parse_register_flag("true").unwrap(), Some(true));
        assert_eq!(parse_register_flag("0").unwrap(), Some(false));
        assert!(parse_register_flag("").unwrap().is_none());
        assert!(parse_register_flag("maybe").is_err());
    }
}

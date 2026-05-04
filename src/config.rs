use serde::Deserialize;
use std::path::PathBuf;

#[derive(Debug, Deserialize, Clone)]
pub struct AppConfig {
    pub server: ServerConfig,
    pub repositories: Vec<RepositoryConfig>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct ServerConfig {
    pub port: u16,
    pub refresh_interval: u64, // in seconds
}

#[derive(Debug, Deserialize, Clone)]
pub struct RepositoryConfig {
    pub name: String,
    pub path: String,
    pub branch: String, // e.g., "main"
    pub remotes: Vec<RemoteConfig>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct RemoteConfig {
    pub name: String,
    pub ssh_key: String,
}

impl AppConfig {
    pub fn load() -> Result<Self, config::ConfigError> {
        let settings = config::Config::builder()
            .add_source(config::File::with_name("config.toml"))
            .add_source(config::Environment::with_prefix("GRIG"))
            .build()?;
        
        settings.try_deserialize()
    }
}

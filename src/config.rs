use serde::Deserialize;

#[derive(Debug, Deserialize, Clone)]
pub struct AppConfig {
    pub server: ServerConfig,
    pub projects: Vec<ProjectConfig>, // Renamed from repositories
}

#[derive(Debug, Deserialize, Clone)]
pub struct ServerConfig {
    pub port: u16,
    pub refresh_interval: u64,
}

#[derive(Debug, Deserialize, Clone)]
pub struct ProjectConfig {
    pub name: String,
    pub branch: String,
    pub remotes: Vec<RemoteConfig>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct RemoteConfig {
    pub name: String,
    pub url: String, // Added URL to the config
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

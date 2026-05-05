mod config;
mod git_ops;

use axum::{extract::State, response::Html, routing::get, Json, Router};
use chrono::{DateTime, Utc};
use config::AppConfig;
use serde::Serialize;
use std::{collections::HashMap, sync::Arc};
use tokio::{net::TcpListener, sync::RwLock};
use tracing::{error, info};

// --- Models ---

#[derive(Clone)]
struct AppState {
    config: Arc<AppConfig>,
    // Key: project_name -> Value: ProjectStatus
    statuses: Arc<RwLock<HashMap<String, ProjectStatus>>>,
}

#[derive(Clone, Serialize)]
struct ProjectStatus {
    project_name: String,
    is_synced: bool,
    remotes: Vec<RemoteStatus>,
}

#[derive(Clone, Serialize)]
struct RemoteStatus {
    remote_name: String,
    hash: Option<String>,
    last_checked: DateTime<Utc>,
    error_msg: Option<String>,
}

#[derive(Serialize)]
struct DashboardResponse {
    global_sync: bool,
    projects: Vec<ProjectStatus>,
}

// --- Main ---

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();

    info!("Starting Stateless GRIG (Git Remote Integrity Guard)...");

    let app_config = Arc::new(AppConfig::load().expect("Failed to load config.toml"));
    let statuses = Arc::new(RwLock::new(HashMap::new()));

    let state = AppState {
        config: app_config.clone(),
        statuses: statuses.clone(),
    };

    // Spawn the background polling task
    let state_for_worker = state.clone();
    tokio::spawn(async move {
        run_background_poller(state_for_worker).await;
    });

    // Setup Axum Router
    let app = Router::new()
        .route("/", get(root_handler))
        .route("/api/v1/status", get(status_handler))
        .with_state(state);

    let addr = format!("0.0.0.0:{}", app_config.server.port);
    let listener = TcpListener::bind(&addr).await?;
    
    info!("Server listening on {}", addr);
    axum::serve(listener, app).await?;

    Ok(())
}

// --- Background Worker ---

async fn run_background_poller(state: AppState) {
    let interval_secs = state.config.server.refresh_interval;
    
    loop {
        info!("Starting stateless git integrity sweep...");
        
        for project in &state.config.projects {
            let mut current_project_status = ProjectStatus {
                project_name: project.name.clone(),
                is_synced: false,
                remotes: Vec::new(),
            };

            let mut unique_hashes = std::collections::HashSet::new();
            let mut has_errors = false;

            for remote in &project.remotes {
                let branch = project.branch.clone();
                let remote_cfg = remote.clone();
                
                // Fetch the hash directly from the remote URL
                let fetch_result = tokio::task::spawn_blocking(move || {
                    git_ops::fetch_remote_hash(&branch, &remote_cfg)
                })
                .await
                .unwrap();

                let mut r_status = RemoteStatus {
                    remote_name: remote.name.clone(),
                    hash: None,
                    last_checked: Utc::now(),
                    error_msg: None,
                };

                match fetch_result {
                    Ok(hash) => {
                        let short_hash = hash[..7].to_string();
                        r_status.hash = Some(short_hash.clone());
                        unique_hashes.insert(short_hash);
                    }
                    Err(e) => {
                        error!("Failed to read remote {}: {}", remote.name, e);
                        r_status.error_msg = Some(e.to_string());
                        has_errors = true;
                    }
                }
                
                current_project_status.remotes.push(r_status);
            }

            // Integrity Check: If all remotes returned a hash, and there is exactly 1 unique hash, they match!
            current_project_status.is_synced = !has_errors && unique_hashes.len() == 1;

            // Update the shared state
            state.statuses.write().await.insert(project.name.clone(), current_project_status);
        }
        
        info!("Sweep complete. Sleeping for {} seconds.", interval_secs);
        tokio::time::sleep(tokio::time::Duration::from_secs(interval_secs)).await;
    }
}

// --- API Handlers ---

async fn root_handler() -> Html<&'static str> {
    // This macro embeds the HTML file into your compiled binary
    Html(include_str!("index.html"))
}

async fn status_handler(State(state): State<AppState>) -> Json<DashboardResponse> {
    let lock = state.statuses.read().await;
    let projects: Vec<ProjectStatus> = lock.values().cloned().collect();
    
    // Global sync is true if EVERY project is synced
    let global_sync = projects.iter().all(|p| p.is_synced);

    Json(DashboardResponse {
        global_sync,
        projects,
    })
}

mod config;
mod git_ops;

use axum::{extract::State, routing::get, Json, Router};
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
    // Key: "repo_name::remote_name" -> Value: RemoteStatus
    statuses: Arc<RwLock<HashMap<String, RemoteStatus>>>,
}

#[derive(Clone, Serialize)]
struct RemoteStatus {
    repo_name: String,
    remote_name: String,
    local_hash: Option<String>,
    remote_hash: Option<String>,
    is_synced: bool,
    last_checked: DateTime<Utc>,
    error_msg: Option<String>,
}

#[derive(Serialize)]
struct DashboardResponse {
    global_sync: bool,
    remotes: Vec<RemoteStatus>,
}

// --- Main ---

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();

    info!("Starting GRIG (Git Remote Integrity Guard)...");

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
        info!("Starting git integrity sweep...");
        
        for repo in &state.config.repositories {
            for remote in &repo.remotes {
                let cache_key = format!("{}::{}", repo.name, remote.name);
                
                // Clone data for the blocking thread
                let repo_path = repo.path.clone();
                let branch = repo.branch.clone();
                let remote_cfg = remote.clone();
                
                // CRITICAL: Move synchronous libgit2 operations off the async runtime
                let check_result = tokio::task::spawn_blocking(move || {
                    git_ops::check_remote_sync(&repo_path, &branch, &remote_cfg)
                })
                .await
                .unwrap(); // Unwrap the thread panic, not the GitError

                let mut status = RemoteStatus {
                    repo_name: repo.name.clone(),
                    remote_name: remote.name.clone(),
                    local_hash: None,
                    remote_hash: None,
                    is_synced: false,
                    last_checked: Utc::now(),
                    error_msg: None,
                };

                match check_result {
                    Ok(sync_data) => {
                        status.local_hash = Some(sync_data.local_hash[..7].to_string());
                        status.remote_hash = Some(sync_data.remote_hash[..7].to_string());
                        status.is_synced = sync_data.is_synced;
                    }
                    Err(e) => {
                        error!("Sync check failed for {}: {}", cache_key, e);
                        status.error_msg = Some(e.to_string());
                    }
                }

                // Update the shared state
                state.statuses.write().await.insert(cache_key, status);
            }
        }
        
        info!("Sweep complete. Sleeping for {} seconds.", interval_secs);
        tokio::time::sleep(tokio::time::Duration::from_secs(interval_secs)).await;
    }
}

// --- API Handler ---

async fn status_handler(State(state): State<AppState>) -> Json<DashboardResponse> {
    let lock = state.statuses.read().await;
    let remotes: Vec<RemoteStatus> = lock.values().cloned().collect();
    
    let global_sync = remotes.iter().all(|r| r.is_synced && r.error_msg.is_none());

    Json(DashboardResponse {
        global_sync,
        remotes,
    })
}

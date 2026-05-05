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
    last_checked: chrono::DateTime<chrono::Utc>,
    error_msg: Option<String>,
}

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
                    last_checked: chrono::Utc::now(),
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

            // Update the shared state (assuming you refactor state to store ProjectStatus instead of RemoteStatus)
            state.statuses.write().await.insert(project.name.clone(), current_project_status);
        }
        
        tokio::time::sleep(tokio::time::Duration::from_secs(interval_secs)).await;
    }
}

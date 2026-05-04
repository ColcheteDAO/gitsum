use crate::config::RemoteConfig;
use git2::{Cred, RemoteCallbacks, Repository};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum GitCheckError {
    #[error("Git error: {0}")]
    Git(#[from] git2::Error),
    #[error("Branch {0} not found locally")]
    LocalBranchNotFound(String),
    #[error("Branch {0} not found on remote")]
    RemoteBranchNotFound(String),
}

pub struct SyncResult {
    pub local_hash: String,
    pub remote_hash: String,
    pub is_synced: bool,
}

pub fn check_remote_sync(
    repo_path: &str,
    branch_name: &str,
    remote_config: &RemoteConfig,
) -> Result<SyncResult, GitCheckError> {
    let repo = Repository::open(repo_path)?;

    // 1. Get Local OID
    let local_ref_name = format!("refs/heads/{}", branch_name);
    let local_oid = repo
        .find_reference(&local_ref_name)
        .map_err(|_| GitCheckError::LocalBranchNotFound(branch_name.to_string()))?
        .target()
        .ok_or_else(|| GitCheckError::LocalBranchNotFound("Invalid target".into()))?;

    // 2. Setup SSH Callbacks
    let mut callbacks = RemoteCallbacks::new();
    let ssh_key_path = remote_config.ssh_key.clone();
    
    callbacks.credentials(move |_url, username_from_url, _allowed_types| {
        Cred::ssh_key(
            username_from_url.unwrap_or("git"),
            None,
            std::path::Path::new(&ssh_key_path),
            None,
        )
    });

    // 3. Connect to Remote and List References (ls-remote approach)
    let mut remote = repo.find_remote(&remote_config.name)?;
    
    // We only connect, we do not fetch the actual objects
    remote.connect_auth(git2::Direction::Fetch, Some(callbacks), None)?;
    
    let remote_refs = remote.list()?;
    let remote_ref_name = format!("refs/heads/{}", branch_name);
    
    let remote_oid = remote_refs
        .iter()
        .find(|r| r.name() == remote_ref_name)
        .map(|r| r.oid())
        .ok_or_else(|| GitCheckError::RemoteBranchNotFound(branch_name.to_string()))?;

    // 4. Compare
    Ok(SyncResult {
        local_hash: local_oid.to_string(),
        remote_hash: remote_oid.to_string(),
        is_synced: local_oid == remote_oid,
    })
}

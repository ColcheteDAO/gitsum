use crate::config::RemoteConfig;
use git2::{CertificateCheckStatus, Cred, Remote, RemoteCallbacks};
use std::path::Path;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum GitCheckError {
    #[error("Git error: {0}")]
    Git(#[from] git2::Error),
    #[error("Branch {0} not found on remote")]
    RemoteBranchNotFound(String),
}

pub fn fetch_remote_hash(
    branch_name: &str,
    remote_config: &RemoteConfig,
) -> Result<String, GitCheckError> {
    
    // 1. Create a detached remote
    let mut remote = Remote::create_detached(remote_config.url.as_str())?;

    // 2. Setup SSH Callbacks
    let mut callbacks = RemoteCallbacks::new();
    let ssh_key_path = remote_config.ssh_key.clone();
    
    // Create the path to the public key (e.g., id_ed25519.pub)
    let pub_key_path = format!("{}.pub", ssh_key_path);
    
    callbacks.certificate_check(|_cert, _valid| {
        Ok(CertificateCheckStatus::CertificateOk)
    });

    callbacks.credentials(move |_url, username_from_url, _allowed_types| {
        Cred::ssh_key(
            username_from_url.unwrap_or("git"),
            Some(Path::new(&pub_key_path)), // <-- Explicitly pass the public key here
            Path::new(&ssh_key_path),
            None,
        )
    });

    // 3. Connect and perform an in-memory ls-remote
    remote.connect_auth(git2::Direction::Fetch, Some(callbacks), None)?;
    
    let remote_refs = remote.list()?;
    let target_ref_name = format!("refs/heads/{}", branch_name);
    
    let remote_oid = remote_refs
        .iter()
        .find(|r| r.name() == target_ref_name)
        .map(|r| r.oid())
        .ok_or_else(|| GitCheckError::RemoteBranchNotFound(branch_name.to_string()))?;

    Ok(remote_oid.to_string())
}

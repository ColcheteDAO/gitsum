# Gitsum: Git Remote Integrity Guard

[![Docker Build Status](https://img.shields.io/badge/build-GHCR-blue)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](#)

**Gitsum** is a stateless, high-performance monitoring and automation toolkit developed by [ColcheteDAO](https://github.com/ColcheteDAO). It is designed to ensure synchronization and integrity across multiple Git remotes without the overhead of heavy local repository clones. 

By leveraging in-memory SSH checks, Gitsum verifies remote branch hashes in real-time, providing immediate visibility through an embedded web dashboard.

---

## 🏗 Architecture & Tech Stack

* **Core Engine:** Rust (High-performance, stateless in-memory polling).
* **Web Dashboard:** Vanilla JavaScript & HTML (Self-contained, lightweight visualization).
* **Infrastructure:** Multi-stage Docker containerization, orchestrated via Docker Compose.
* **Automation:** Bash scripts for GitHub repository auto-discovery and Gitea SSH mirroring.

---

## 🚀 Getting Started (Local Environment)

As a stateless service, running Gitsum locally is highly streamlined. The application relies entirely on Docker, keeping your host machine clean.

### Prerequisites

* **Docker & Docker Compose:** Ensure you have the latest versions installed.
* **Git:** Required for cloning this repository.
* **SSH Keys & Access Tokens:** 
  * An active SSH keypair (`GIT_SUM` format recommended) authorized on your target remotes (GitHub/Gitea).
  * A GitHub Personal Access Token (PAT) named `GITSUM` with `read` scopes for repository discovery.

### 1. Clone the Repository

```bash
git clone git@github.com:ColcheteDAO/gitsum.git
cd gitsum
```

### 2. Environment Configuration

Copy the example environment file and configure your credentials.

```bash
cp .env.example .env
```

Edit the `.env` file to include your specific paths and tokens:

```env
# GitHub Configuration
GITHUB_PAT=<YOUR_GITSUM_TOKEN>
GITHUB_ORG=ColcheteDAO

# SSH Configuration
# Ensure this points to the private key corresponding to your registered GIT_SUM public key
SSH_PRIVATE_KEY_PATH=./secrets/id_rsa_gitsum

# Web Dashboard Port
PORT=8080
```

> ⚠️ **Security Warning:** Never commit your `.env` file or any files inside the `./secrets/` directory to version control.

### 3. Provisioning Secrets

Create a local directory to securely mount your SSH keys into the container:

```bash
mkdir -p secrets

# Copy your private key to the secrets directory
cp ~/.ssh/id_rsa_gitsum ./secrets/id_rsa_gitsum

# Ensure strict read-only permissions are set
chmod 600 ./secrets/id_rsa_gitsum
```

### 4. Build and Run

Launch the multi-stage container using Docker Compose:

```bash
docker-compose up -d --build
```

The system will start polling the configured remotes. You can access the unified web dashboard at: **`http://localhost:8080`**

---

## 🧪 QA & Testing Operations

To maintain the integrity of the Gitsum service, run the following checks before committing changes or pushing to trigger GitHub Actions.

### Viewing Logs

Monitor the real-time polling and check for SSH host key verification errors:

```bash
docker-compose logs -f gitsum-service
```

### Running the Rust Test Suite

To run the unit and integration tests locally (requires the Rust toolchain):

```bash
cargo test --workspace
```

### Linting & Formatting

Ensure code adheres to the project standards to prevent CI/CD failures on GHCR builds:

```bash
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
```

## 🛑 Troubleshooting

* **SSH Authentication Failures:** If Gitsum fails to poll memory hashes, verify that the `GIT_SUM` public key is correctly added to your GitHub/Gitea accounts and that the container has the correct read permissions (`chmod 600`) on the mounted private key.
* **GitHub Actions Build Failures:** Check the repository's CI/CD pipeline logs. Recent workflow failures are often tied to multi-stage Docker caching or incorrect secret mapping in the GHCR publication step. Ensure your local `docker-compose build` succeeds first.

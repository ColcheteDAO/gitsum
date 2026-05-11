#!/usr/bin/env bash
# Exit immediately if a command fails, treat unset variables as an error
set -euo pipefail

# --- Load Environment Variables ---
if [ -f ".env" ]; then
  echo "Loading variables from .env file..."
  set -a
  source .env
  set +a
fi

# --- Configuration ---
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$GITHUB_TOKEN" ]; then
  echo "ERROR: Please set your GITHUB_TOKEN environment variable or add it to a .env file."
  exit 1
fi

SERVER_PORT=3000
REFRESH_INTERVAL=60
OUTPUT_FILE="config.toml"

# --- Parse Extra Remotes via Templates ---
EXTRA_REMOTES="${EXTRA_REMOTES:-}"
EXTRA_REMOTES_JSON="[]"

if [ -n "$EXTRA_REMOTES" ]; then
  EXTRA_REMOTES_JSON=$(echo "$EXTRA_REMOTES" | tr ' ' '\n' | jq -R -s -c '
    split("\n") | map(select(length > 0)) | map(split(",")) | map({"name": .[0], "url_template": .[1]})
  ')
  echo "Detected extra remotes. Appending them to each project..."
fi

echo "Initializing $OUTPUT_FILE..."
cat <<EOF > "$OUTPUT_FILE"
[server]
port = $SERVER_PORT
refresh_interval = $REFRESH_INTERVAL

EOF

# --- Helper Function ---
append_repos() {
  local base_url="$1"
  local page=1

  while true; do
    local url="${base_url}"
    if [[ "$url" == *"?"* ]]; then
      url="${url}&per_page=100&page=${page}"
    else
      url="${url}?per_page=100&page=${page}"
    fi

    local body
    if ! body=$(curl -sS -f -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" "$url"); then
        echo "⚠️  Failed to fetch $url (Check permissions). Skipping..."
        break
    fi
    
    local count
    count=$(echo "$body" | jq 'length')
    if [ "$count" -eq 0 ]; then
      break
    fi

    # Use jq to create ONE [[projects]] block, and loop remotes inside it.
    echo "$body" | jq -r --argjson extras "$EXTRA_REMOTES_JSON" '
      .[] | 
      . as $repo |
      "[[projects]]\n" +
      "name = \"\($repo.name)\"\n" +
      "branch = \"\(if $repo.default_branch != null then $repo.default_branch else "main" end)\"\n" +
      (
        ( [{"name": "github", "url_template": "git@github.com:{full_name}.git" }] + $extras ) | map(
          "\n  [[projects.remotes]]\n" +
          "  name = \"\(.name)\"\n" +
          "  url = \"\(.url_template | gsub("\\{full_name\\}"; $repo.full_name) | gsub("\\{owner\\}"; $repo.owner.login) | gsub("\\{name\\}"; $repo.name))\"\n" +
          "  ssh_key = \"/etc/gitsum/keys/\(.name)\"\n"
        ) | join("")
      ) + "\n"
    ' >> "$OUTPUT_FILE"

    page=$((page + 1))
  done
}

# --- Main Execution ---

echo "Fetching user repositories..."
append_repos "https://api.github.com/user/repos?type=owner"

echo "Fetching organizations..."
if orgs=$(curl -sS -f -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/user/orgs"); then
    for org in $(echo "$orgs" | jq -r '.[].login'); do
      echo "Fetching repositories for organization: $org..."
      append_repos "https://api.github.com/orgs/${org}/repos?type=all"
    done
else
    echo "⚠️  Failed to fetch organizations."
fi

PROJECT_COUNT=$(grep -c "\[\[projects\]\]" "$OUTPUT_FILE" || true)
echo "✅ Successfully generated $OUTPUT_FILE with $PROJECT_COUNT grouped projects!"

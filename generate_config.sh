#!/usr/bin/env bash
# Exit immediately if a command fails, treat unset variables as an error
set -euo pipefail

# --- Load Environment Variables ---
# If a .env file exists in the current directory, source it safely
if [ -f ".env" ]; then
  echo "Loading variables from .env file..."
  # Export variables from .env, ignoring comments and empty lines
  export $(grep -v '^#' .env | xargs)
fi

# --- Configuration ---
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$GITHUB_TOKEN" ]; then
  echo "ERROR: Please set your GITHUB_TOKEN environment variable or add it to a .env file."
  echo "Example .env content: GITHUB_TOKEN=ghp_your_actual_token_here"
  exit 1
fi

SERVER_PORT=3000
REFRESH_INTERVAL=60
OUTPUT_FILE="config.toml"

echo "Initializing $OUTPUT_FILE..."
cat <<EOF > "$OUTPUT_FILE"
[server]
port = $SERVER_PORT
refresh_interval = $REFRESH_INTERVAL

EOF

# --- Helper Function ---
# Fetches paginated API endpoints and uses jq to format directly to TOML
append_repos() {
  local base_url="$1"
  local page=1

  while true; do
    # Handle URL parameter appending
    local url="${base_url}"
    if [[ "$url" == *"?"* ]]; then
      url="${url}&per_page=100&page=${page}"
    else
      url="${url}?per_page=100&page=${page}"
    fi

    local body
    # Fetch the page; exit the loop gracefully if the API call fails
    if ! body=$(curl -sS -f -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" "$url"); then
        echo "⚠️  Failed to fetch $url (Check permissions). Skipping..."
        break
    fi
    
    # If the returned JSON array is empty, we've reached the end of the pages
    local count
    count=$(echo "$body" | jq 'length')
    if [ "$count" -eq 0 ]; then
      break
    fi

    # Use jq to map the JSON array directly into the TOML string format
    echo "$body" | jq -r '
      .[] | 
      "[[projects]]\n" +
      "name = \"\(.name)\"\n" +
      "branch = \"\(if .default_branch != null then .default_branch else "main" end)\"\n\n" +
      "  [[projects.remotes]]\n" +
      "  name = \"github\"\n" +
      "  url = \"git@github.com:\(.full_name).git\"\n" +
      "  ssh_key = \"/etc/gitsum/keys/github\"\n"
    ' >> "$OUTPUT_FILE"

    page=$((page + 1))
  done
}

# --- Main Execution ---

echo "Fetching user repositories..."
append_repos "https://api.github.com/user/repos?type=owner"

echo "Fetching organizations..."
if orgs=$(curl -sS -f -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/user/orgs"); then
    
    # Loop through each organization login name
    for org in $(echo "$orgs" | jq -r '.[].login'); do
      echo "Fetching repositories for organization: $org..."
      append_repos "https://api.github.com/orgs/${org}/repos?type=all"
    done
else
    echo "⚠️  Failed to fetch organizations."
fi

# Count the number of generated projects
PROJECT_COUNT=$(grep -c "\[\[projects\]\]" "$OUTPUT_FILE" || true)
echo "✅ Successfully generated $OUTPUT_FILE with $PROJECT_COUNT repositories!"

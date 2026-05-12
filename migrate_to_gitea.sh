#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="config.toml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: $CONFIG_FILE not found."
    exit 1
fi

echo "📖 Reading $CONFIG_FILE natively..."

# Create a temporary directory for cloning
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "🚀 Starting universal migration..."

CURRENT_PROJECT=""
CURRENT_REMOTE=""
GITHUB_URL=""
GITHUB_KEY=""
EXTRA_TARGETS=""

# Execute migration for the parsed project
execute_migration() {
    if [[ -z "$GITHUB_URL" || -z "$CURRENT_PROJECT" || -z "$EXTRA_TARGETS" ]]; then
        return
    fi

    echo "--------------------------------------------------------"
    echo "📦 Migrating: $CURRENT_PROJECT"
    
    REPO_DIR="$TEMP_DIR/$CURRENT_PROJECT.git"

    # 1. Clone a "bare" repo from GitHub
    echo "   ⬇️  Cloning from GitHub..."
    if ! GIT_SSH_COMMAND="ssh -i $GITHUB_KEY -o StrictHostKeyChecking=no" git clone --quiet --bare "$GITHUB_URL" "$REPO_DIR"; then
        echo "   ❌ Failed to clone $CURRENT_PROJECT from GitHub. Skipping..."
        return
    fi

    # 2. Push to ALL extra remotes found in the config
    pushd "$REPO_DIR" > /dev/null || return
    
    while IFS='|' read -r t_name t_url t_key; do
        [[ -z "$t_name" ]] && continue
        echo "   ⬆️  Pushing mirror to $t_name ($t_url)..."
        
        if GIT_SSH_COMMAND="ssh -i $t_key -o StrictHostKeyChecking=no" git push --quiet --mirror "$t_url"; then
            echo "   ✅ Successfully mirrored to $t_name!"
        else
            echo "   ❌ Failed to push to $t_name."
        fi
    done <<< "$EXTRA_TARGETS"
    
    popd > /dev/null || return
}

# --- TOML Parser Loop ---
while IFS= read -r line || [[ -n "$line" ]]; do
    # SAFE WHITESPACE TRIM: Uses sed instead of xargs to preserve quotation marks
    line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Ignore comments and empty lines
    if [[ -z "$line" || "$line" == \#* ]]; then
        continue
    fi

    # Detect a new project block
    if [[ "$line" == "[[projects]]" ]]; then
        if [[ -n "$CURRENT_PROJECT" ]]; then
            execute_migration
        fi
        # Reset variables for the new project
        CURRENT_PROJECT=""
        GITHUB_URL=""
        GITHUB_KEY=""
        EXTRA_TARGETS=""
        CURRENT_REMOTE=""
        continue
    fi

    # Capture the project name
    if [[ "$line" == name\ =* && -z "$CURRENT_REMOTE" ]]; then
        CURRENT_PROJECT=$(echo "$line" | sed -n 's/.*"\(.*\)".*/\1/p')
        continue
    fi

    # Detect a new remote block
    if [[ "$line" == "[[projects.remotes]]" ]]; then
        CURRENT_REMOTE="pending"
        T_URL=""
        T_KEY=""
        continue
    fi

    # Capture remote name
    if [[ "$line" == name\ =* && "$CURRENT_REMOTE" == "pending" ]]; then
        CURRENT_REMOTE=$(echo "$line" | sed -n 's/.*"\(.*\)".*/\1/p')
        continue
    fi

    # Capture GitHub details (Source)
    if [[ "$CURRENT_REMOTE" == "github" ]]; then
        if [[ "$line" == url\ =* ]]; then
            GITHUB_URL=$(echo "$line" | sed -n 's/.*"\(.*\)".*/\1/p')
        elif [[ "$line" == ssh_key\ =* ]]; then
            GITHUB_KEY=$(echo "$line" | sed -n 's/.*"\(.*\)".*/\1/p')
        fi
        continue
    fi

    # Capture Any Other Remote details (Targets)
    if [[ -n "$CURRENT_REMOTE" && "$CURRENT_REMOTE" != "github" && "$CURRENT_REMOTE" != "pending" ]]; then
        if [[ "$line" == url\ =* ]]; then
            T_URL=$(echo "$line" | sed -n 's/.*"\(.*\)".*/\1/p')
        elif [[ "$line" == ssh_key\ =* ]]; then
            T_KEY=$(echo "$line" | sed -n 's/.*"\(.*\)".*/\1/p')
        fi
        
        # Once we have both URL and Key, save it to our targets list
        if [[ -n "${T_URL:-}" && -n "${T_KEY:-}" ]]; then
            EXTRA_TARGETS="${EXTRA_TARGETS}${CURRENT_REMOTE}|${T_URL}|${T_KEY}"$'\n'
            T_URL=""
            T_KEY=""
        fi
        continue
    fi

done < "$CONFIG_FILE"

# Make sure to migrate the very last project in the file
if [[ -n "$CURRENT_PROJECT" ]]; then
    execute_migration
fi

echo "--------------------------------------------------------"
echo "🎉 Migration complete! Temporary files cleaned up."

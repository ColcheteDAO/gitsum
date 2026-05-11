#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
CONFIG_FILE="config.toml"
TARGET_REMOTE="gitea" # Ensure this matches the name of your extra remote

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: $CONFIG_FILE not found."
    exit 1
fi

echo "📖 Reading $CONFIG_FILE natively..."

# Create a temporary directory for cloning
TEMP_DIR=$(mktemp -d)
# Ensure the temp directory is deleted when the script exits or crashes
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "🚀 Starting migration from GitHub to $TARGET_REMOTE..."

# We will read the config line by line to keep track of the current project and remote
CURRENT_PROJECT=""
CURRENT_REMOTE=""

# Project-specific variables
GITHUB_URL=""
GITHUB_KEY=""
TARGET_URL=""
TARGET_KEY=""

# Function to execute the migration once a project block is fully parsed
execute_migration() {
    # If we haven't collected both URLs yet, do nothing and return
    if [[ -z "$GITHUB_URL" || -z "$TARGET_URL" || -z "$CURRENT_PROJECT" ]]; then
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

    # 2. Push an exact mirror to the Target Remote
    echo "   ⬆️  Pushing mirror to $TARGET_REMOTE..."
    pushd "$REPO_DIR" > /dev/null || return
    
    if GIT_SSH_COMMAND="ssh -i $TARGET_KEY -o StrictHostKeyChecking=no" git push --quiet --mirror "$TARGET_URL"; then
        echo "   ✅ Successfully mirrored $CURRENT_PROJECT to $TARGET_REMOTE!"
    else
        echo "   ❌ Failed to push $CURRENT_PROJECT to $TARGET_REMOTE."
        echo "      (Did you enable ENABLE_PUSH_CREATE=true in Gitea's app.ini?)"
    fi
    
    popd > /dev/null || return
}

# --- TOML Parser Loop ---
# This loop reads the config.toml file line by line to extract the needed strings.
while IFS= read -r line || [[ -n "$line" ]]; do
    # Remove leading/trailing whitespace
    line=$(echo "$line" | xargs)

    # Ignore comments and empty lines
    if [[ -z "$line" || "$line" == \#* ]]; then
        continue
    fi

    # Detect a new project block
    if [[ "$line" == "[[projects]]" ]]; then
        # If we were tracking a previous project, migrate it before resetting
        if [[ -n "$CURRENT_PROJECT" && -n "$TARGET_URL" ]]; then
            execute_migration
        fi
        # Reset variables for the new project
        CURRENT_PROJECT=""
        GITHUB_URL=""
        GITHUB_KEY=""
        TARGET_URL=""
        TARGET_KEY=""
        CURRENT_REMOTE=""
        continue
    fi

    # Capture the project name
    if [[ "$line" == name\ =* && -z "$CURRENT_REMOTE" ]]; then
        # Extract the value between the quotes
        CURRENT_PROJECT=$(echo "$line" | sed -n 's/.*"\(.*\)".*/\1/p')
        continue
    fi

    # Detect a new remote block inside the project
    if [[ "$line" == "[[projects.remotes]]" ]]; then
        CURRENT_REMOTE="pending"
        continue
    fi

    # Capture which remote we are currently parsing
    if [[ "$line" == name\ =* && "$CURRENT_REMOTE" == "pending" ]]; then
        CURRENT_REMOTE=$(echo "$line" | sed -n 's/.*"\(.*\)".*/\1/p')
        continue
    fi

    # Capture GitHub details
    if [[ "$CURRENT_REMOTE" == "github" ]]; then
        if [[ "$line" == url\ =* ]]; then
            GITHUB_URL=$(echo "$line" | sed -n 's/.*"\(.*\)".*/\1/p')
        elif [[ "$line" == ssh_key\ =* ]]; then
            GITHUB_KEY=$(echo "$line" | sed -n 's/.*"\(.*\)".*/\1/p')
        fi
        continue
    fi

    # Capture Target Remote details
    if [[ "$CURRENT_REMOTE" == "$TARGET_REMOTE" ]]; then
        if [[ "$line" == url\ =* ]]; then
            TARGET_URL=$(echo "$line" | sed -n 's/.*"\(.*\)".*/\1/p')
        elif [[ "$line" == ssh_key\ =* ]]; then
            TARGET_KEY=$(echo "$line" | sed -n 's/.*"\(.*\)".*/\1/p')
        fi
        continue
    fi

done < "$CONFIG_FILE"

# Make sure to migrate the very last project in the file
if [[ -n "$CURRENT_PROJECT" && -n "$TARGET_URL" ]]; then
    execute_migration
fi

echo "--------------------------------------------------------"
echo "🎉 Migration complete! Temporary files cleaned up."

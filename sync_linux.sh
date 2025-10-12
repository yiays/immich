#!/bin/bash

# ==============================================================================
# Syncs a local backup file to a remote server with retry logic
# ==============================================================================

# --- Configuration ---
LOCAL_BACKUP_DIR="/mnt/immich/offsite"
REMOTE_HOST="nz2"
REMOTE_DIR="/mnt/immich"
MAX_RETRIES=12
RETRY_DELAY_SECONDS=3600  # 1 hour

# --- Main Script ---

echo "Searching for backup file in $LOCAL_BACKUP_DIR..."

cd "$LOCAL_BACKUP_DIR" || exit 1

# Find the newest file in the directory.
# 'ls -t' sorts by modification time, and 'head -n 1' gets the first (newest) result.
FILE=$(ls -t | head -n 1)

if [ -z "$FILE" ]; then
    echo "Failed to find a backup file. Exiting."
    exit 1
fi

echo "Backup file found: $FILE"

echo "Copying backup to remote server..."

ATTEMPT=1
SUCCESS=0

while [ $ATTEMPT -le $MAX_RETRIES ]; do
    echo "--- Attempt $ATTEMPT of $MAX_RETRIES ---"

    # Step 1: Delete old backups on the remote server
    # The command is enclosed in quotes for SSH to execute it remotely.
    ssh "$REMOTE_HOST" "rm -f $REMOTE_DIR/*"

    if [ $? -eq 0 ]; then
        echo "Connection to backup site established."
        SUCCESS=1
        break # Exit the loop on success
    else
        echo "Connection to backup site failed. Waiting $RETRY_DELAY_SECONDS seconds before next attempt..."
        sleep "$RETRY_DELAY_SECONDS"
        ATTEMPT=$((ATTEMPT + 1))
    fi
done

if [ $SUCCESS -eq 0 ]; then
    echo "Failed to connect to $REMOTE_HOST after $MAX_RETRIES attempts. Exiting."
    discord.sh --webhook-url "$WEBHOOK_URL" --text "Failed to sync Immich backup to $REMOTE_HOST"
    exit 1
fi

# Step 2: Copy the new backup file
scp "$FILE" "${REMOTE_HOST}:${REMOTE_DIR}"
if [ $? -eq 0 ]; then
    echo "Sucesfully copied backup to backup site."
else
    echo "Failed to finish copying backup to backup site."
    discord.sh --webhook-url "$WEBHOOK_URL" --text "Interrupted sync of Immich backup to $REMOTE_HOST"
fi

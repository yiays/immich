#!/bin/bash

# ====================================================================
# Backs up an immich instance, then syncs to two servers;
#   One local (LAN), one remote, as a part of a 3-2-1 backup strategy
#   Both Windows (10, 11) and Linux (bash, rsync) are supported.
# ====================================================================

# Always start in the script directory
cd "${0%/*}"

# Load environment variables from .env if it exists
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file missing, unable to continue" 1>&2
    exit 1
fi

# Set the backup directory all functions will share
LOCAL_BACKUP_DIR="$UPLOAD_LOCATION/offsite"

# Generate a timestamp for the backup file
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_FILE="backup-$TIMESTAMP.tar.gz.gpg"

# backup
backup() {
    # Stores all essential immich data in a compressed and encrypted file

    cd $UPLOAD_LOCATION
    # List of directories to back up (relative to the user's home directory)
    SOURCE_DIRS=( "backups" "library" "upload" "profile" )

    # --- Main Script ---

    rm -f $LOCAL_BACKUP_DIR/*

    echo "Starting backup of directories: ${SOURCE_DIRS[@]}"
    echo "Compressing and encrypting with AES256..."

    # Use tar to create an archive, pipe it to gzip for compression, then pipe to gpg for encryption.
    tar -czf - "${SOURCE_DIRS[@]}" 2> /dev/null | gpg --symmetric --cipher-algo AES256 --batch --yes --passphrase-fd 3 -o "$LOCAL_BACKUP_DIR/$BACKUP_FILE" 3<<< "$PASSWORD"

    # Check the exit status of the last command
    if [ $? -eq 0 ]; then
        echo "Backup completed successfully."
        echo "File stored at: $LOCAL_BACKUP_DIR/$BACKUP_FILE"
    else
        echo "Error: Backup failed. Please check the permissions and file paths." 1>&2
        if [ -n $WEBHOOK_URL ]; then
            discord.sh --webhook-url "$WEBHOOK_URL" --text "Failed to back up Immich"
        fi
        exit 1
    fi
}

# sync PLATFORM HOST DIR
sync() {
    # Connects to a host, deletes old backups, and copies new backups

    cd $LOCAL_BACKUP_DIR

    PLATFORM=$1
    HOST=$2
    DIR=$3

    echo "Establishing connection to $HOST..."

    ATTEMPT=1
    SUCCESS=0

    while [ $ATTEMPT -le $MAX_RETRIES ]; do
        echo "--- Attempt $ATTEMPT of $MAX_RETRIES ---"

        # Delete old backups on the remote server
        if [ $PLATFORM == "windows" ]; then
            ssh "$HOST" "powershell -NoProfile -Command \"Get-ChildItem -Path '$DIR' -File | Sort-Object -Property CreationTime -Descending | Select-Object -Skip 1 | Remove-Item -Force\""
        else
            ssh "$HOST" "cd $DIR && ls -1t | tail -n +2 | xargs -r rm -f --"
        fi

        if [ $? -eq 0 ]; then
            echo "Connection to backup site established."
            SUCCESS=1
            break # Exit the loop on success
        else
            echo "Connection to backup site failed. Waiting $RETRY_DELAY_SECONDS seconds before next attempt..." 1>&2
            sleep "$RETRY_DELAY_SECONDS"
            ATTEMPT=$((ATTEMPT + 1))
        fi
    done

    if [ $SUCCESS -eq 0 ]; then
        echo "Error: Failed to connect to $HOST after $MAX_RETRIES attempts. Exiting." 1>&2
        if [ -n $WEBHOOK_URL ]; then
            discord.sh --webhook-url "$WEBHOOK_URL" --text "Failed to sync Immich backup to $HOST"
        fi
        exit 1
    fi

    echo "Copying backup to remote server..."

    SUCCESS=0

    while [ $ATTEMPT -le $MAX_RETRIES ]; do
        echo "--- Attempt $ATTEMPT of $MAX_RETRIES ---"

        # Copy the new backup file
        if [ $PLATFORM == "windows" ]; then
            # Resumable transfers are sadly not supported on Windows
            ATTEMPT=$MAX_RETRIES
            scp "$BACKUP_FILE" "$HOST:$DIR/$BACKUP_FILE.part"
        else
            rsync --partial "$BACKUP_FILE" "$HOST:$DIR/$BACKUP_FILE.part"
        fi

        if [ $? -eq 0 ]; then
            echo "Sucesfully copied backup to backup site."
            # Rename the backup file when the copy is complete
            if [ $PLATFORM == "windows" ]; then
                ssh "$HOST" "powershell Rename-Item $DIR/$BACKUP_FILE.part $BACKUP_FILE"
            else
                ssh "$HOST" "mv $DIR/$BACKUP_FILE.part $DIR/$BACKUP_FILE"
            fi
            SUCCESS=1
            break # Exit the loop on success
        else
            sleep "$RETRY_DELAY_SECONDS"
            ATTEMPT=$((ATTEMPT + 1))
        fi
    done

    if [ $SUCCESS -eq 0 ]; then
        echo "Error: Failed to finish copying backup to backup site." 1>&2
        if [ -n $WEBHOOK_URL ]; then
            discord.sh --webhook-url "$WEBHOOK_URL" --text "Interrupted sync of Immich backup to $HOST"
        fi
    fi
}

# --- Main script

backup
if [ $? -ne 0 ]; then
    exit 1
fi

echo "---"

if [ -z $REMOTE_HOST ]; then
    echo "Skipping remote backup as the host is unset."
else
    echo "Waiting $REMOTE_DELAY seconds before syncing to $REMOTE_HOST..."
    sleep $REMOTE_DELAY
    sync $REMOTE_PLATFORM $REMOTE_HOST $REMOTE_DIR
fi

echo "---"

if [ -z $LAN_HOST ]; then
    echo "Skipping local backup as the host is unset."
else
    echo "Waiting $LAN_DELAY seconds before syncing to $LAN_HOST..."
    sleep $LAN_DELAY
    sync $LAN_PLATFORM $LAN_HOST $LAN_DIR
fi

echo "---"

echo "All tasks completed successfully"

#!/bin/bash

# Load environment variables from .env if it exists
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

cd $UPLOAD_LOCATION
# List of directories to back up (relative to the user's home directory)
SOURCE_DIRS=( "backups" "library" "upload" "profile" )

# Destination directory for the encrypted backup file
DEST_DIR="$UPLOAD_LOCATION/offsite"

# --- Main Script ---

# Generate a timestamp for the backup file
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_FILE="backup-$TIMESTAMP.tar.gz.gpg"

rm -f $DEST_DIR/*

echo "Starting backup of directories: ${SOURCE_DIRS[@]}"
echo "Compressing and encrypting with AES256..."

# Use tar to create an archive, pipe it to gzip for compression, then pipe to gpg for encryption.
tar -czf - "${SOURCE_DIRS[@]}" 2> /dev/null | gpg --symmetric --cipher-algo AES256 --batch --yes --passphrase-fd 3 -o "$DEST_DIR/$BACKUP_FILE" 3<<< "$PASSWORD"

# Check the exit status of the last command
if [ $? -eq 0 ]; then
    echo "Backup completed successfully."
    echo "File stored at: $DEST_DIR/$BACKUP_FILE"
else
    echo "Error: Backup failed. Please check the permissions and file paths."
    discord.sh --webhook-url "$WEBHOOK_URL" --text "Failed to back up Immich"
    exit 1
fi



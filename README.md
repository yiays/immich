# Immich 3-2-1 Backup Script

> A small script to export Immich data, encrypt the archive, and sync encrypted backups to Windows and Linux targets.

This script implements a basic and secure method for implementing a 3-2-1 backup of your immich library.

### What is 3-2-1?
**3** backups, stored on **2** different media, **1** of which is remote.
This script creates a local backup, copies it to one local machine, and one remote machine.

## Features
- Export Immich data directory and database dump
- Create an encrypted compressed archive (.tar.gz.gpg)
- Sync encrypted archive to:
  - Linux servers (rsync via ssh)
  - Windows machines (scp)
- Syncing is fault-tolerant and can be configured to retry
- Simple scheduling (cron)
- Any errors can be sent to a Discord webhook
- Also included: a script to upgrade immich, which you could also run on a schedule.

## Prerequisites
- Linux host running Immich
- A local linux or Windows host with SSH and enough storage to hold two backups
  - This could be a gaming computer that's on regularly for example
- A remote linux or Windows host with remote SSH access
  - I would suggest using [tailscale](https://tailscale.com) instead of opening your SSH server to the internet
  - This could be a friend's linux server or a Raspberry Pi plugged into a friend or family's router
- Script dependencies: tar, gzip, gpg, rsync, ssh, scp, discord.sh
  - Download [discord.sh](https://github.com/fieu/discord.sh), make it executable, and place it in your PATH (for example, `~/.local/bin/`)
- SSH passkey access to all destination machines (no password prompt)

## Getting started
- Clone this repository to your home directory
- Copy `.env.example` to `.env` and configure as you see fit
  - Leave `REMOTE_HOST` or `LAN_HOST` empty to skip backups to this destination
  - Fill the `WEBHOOK_URL` variable with a Discord WebHook URL to get alerts whenever a backup or sync fails
- If you don't already have immich installed, this repo can install it for you
  - `sudo docker-compose up -d`
- If you already have immich, ensure UPLOAD_LOCATION in `.env` is consistent with the UPLOAD_LOCATION immich is using
- Ensure the scripts are executable with `chmod +x *.sh`
- Try running a backup with `./backup.sh`
  - This may take hours if you have a large library
- If everything is working well, read the next section to run the backup daily

## Scheduling
- Linux cron (daily at 02:00, as user, not as root):
  - `crontab -e`
  - Append `0 2 * * * /home/me/immich/backup.sh` to the end of the file

## Restore notes
- Copy encrypted file locally
- Decrypt:
  - `gpg --output backup.tar.gz --decrypt backup.tar.gz.gpg --passphrase-fd 0 <<< "PASSWORD"`
- Extract:
  - `tar -xzf backup.tar.gz`
- Restore DB and files per Immich docs (test in staging first)

## Security & best practices
- Test restores regularly
- Limit access to backup storage

## Troubleshooting
- Check permissions on data and backup directories
- Verify network access and credentials for remote targets
- Inspect logs for rsync/ssh/rclone errors (detailed logs are in `mail`)

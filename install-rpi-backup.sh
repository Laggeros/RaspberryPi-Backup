#!/bin/bash
set -e

BACKUP_SCRIPT="/usr/local/bin/rpi-backup.sh"
LOG="/var/log/rpi-backup.log"
CREDS="/root/.smbcredentials-backup"

CRON_TIME="0 3 * * *"
CRON_CMD='sleep $(( RANDOM \% 14400 )); /usr/local/bin/rpi-backup.sh >> /var/log/rpi-backup.log 2>&1'
CRON_LINE="${CRON_TIME} ${CRON_CMD}"

if [[ "$EUID" -ne 0 ]]; then
    echo "This installer must be run as root."
    exit 1
fi

echo "Backup installer"

read -rp "Network share path (SMB/CIFS), e.g. //server/share: " SHARE
while [[ -z "$SHARE" ]]; do read -rp "Enter valid share path: " SHARE; done

read -rp "Local mount point [/mnt/backup]: " MNT
MNT=${MNT:-/mnt/backup}

read -rp "SMB username: " SMBUSER
while [[ -z "$SMBUSER" ]]; do read -rp "SMB username: " SMBUSER; done

read -srp "SMB password: " SMBPASS
echo
while [[ -z "$SMBPASS" ]]; do read -srp "SMB password: " SMBPASS; echo; done

read -rp "Domain / Workgroup [WORKGROUP]: " SMBDOM
SMBDOM=${SMBDOM:-WORKGROUP}

echo "Creating backup script..."

cat > "$BACKUP_SCRIPT" <<'EOF'
#!/bin/bash
set -u

MNT="__MNT__"
SHARE="__SHARE__"
CREDS="/root/.smbcredentials-backup"
LOG="/var/log/rpi-backup.log"
HOST="$(hostname)"
DATE="$(date +%F)"
TARGET="${MNT}/${HOST}-${DATE}"
DIRS="/etc /home /usr/local /var/lib"

if [[ "$EUID" -ne 0 ]]; then exit 1; fi
mkdir -p "$MNT"
echo "START $(date)" >> "$LOG"

if ! mountpoint -q "$MNT"; then
    mount -t cifs "$SHARE" "$MNT" -o "credentials=$CREDS,vers=3.0,_netdev"
    if [[ $? -ne 0 ]]; then echo "MOUNT ERROR $(date)" >> "$LOG"; exit 1; fi
fi

mkdir -p "$TARGET"
for D in $DIRS; do rsync -aAX --ignore-errors --numeric-ids \
 --exclude=/proc/* --exclude=/sys/* --exclude=/dev/* \
 --exclude=/run/* --exclude=/tmp/* --exclude=/mnt/* \
 --exclude=/media/* --exclude=/lost+found \
 "$D" "$TARGET" >> "$LOG" 2>&1; done

find "$MNT" -maxdepth 1 -type d -name "${HOST}-*" -mtime +14 -exec rm -rf {} \; >> "$LOG" 2>&1

echo "END $(date)" >> "$LOG"
EOF

sed -i "s|__MNT__|$MNT|g" "$BACKUP_SCRIPT"
sed -i "s|__SHARE__|$SHARE|g" "$BACKUP_SCRIPT"
chmod +x "$BACKUP_SCRIPT"

mkdir -p "$MNT"
touch "$LOG"
chmod 640 "$LOG"

cat > "$CREDS" <<EOF
username=${SMBUSER}
password=${SMBPASS}
domain=${SMBDOM}
EOF
chmod 600 "$CREDS"

CRONTMP="$(mktemp)"
crontab -l 2>/dev/null > "$CRONTMP" || true
grep -q '^SHELL=/bin/bash' "$CRONTMP" || printf "SHELL=/bin/bash\n%s\n" "$(cat "$CRONTMP")" > "$CRONTMP"
grep -Fq "$CRON_CMD" "$CRONTMP" || echo "$CRON_LINE" >> "$CRONTMP"
crontab "$CRONTMP"
rm -f "$CRONTMP"

echo "Installation complete."
echo "Test: sudo /usr/local/bin/rpi-backup.sh"
echo "Logs: sudo tail -n 50 /var/log/rpi-backup.log"

#!/bin/bash
# Prompt for the Google OAuth client credentials and write them into .env.
set -e
ENV=/home/eggers/crawlseo/.env
read -r -p 'Paste GOOGLE CLIENT ID (ends .apps.googleusercontent.com): ' CID
read -r -s -p 'Paste GOOGLE CLIENT SECRET (input hidden): ' CSEC; echo
[[ $CID == *.apps.googleusercontent.com ]] || { echo 'That does not look like a client ID — aborting, nothing changed.'; exit 1; }
[[ -n $CSEC ]] || { echo 'Empty secret — aborting.'; exit 1; }
python3 - "$CID" "$CSEC" <<'PY'
import sys
cid, csec = sys.argv[1], sys.argv[2]
p = '/home/eggers/crawlseo/.env'
out = []
for line in open(p):
    if line.startswith('GOOGLE_CLIENT_ID='): line = f'GOOGLE_CLIENT_ID={cid}\n'
    elif line.startswith('GOOGLE_CLIENT_SECRET='): line = f'GOOGLE_CLIENT_SECRET={csec}\n'
    out.append(line)
open(p, 'w').writelines(out)
print('written.')
PY
cd /home/eggers/crawlseo && docker compose up -d app
echo 'Done — CrawlSEO restarted with the new credentials.'

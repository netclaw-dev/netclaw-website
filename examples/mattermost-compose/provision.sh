#!/usr/bin/env bash
# Provision a fresh Mattermost: admin, team, private channel, one human user,
# one bot account with an access token. Needs only bash and curl.
#
#   ./provision.sh                      # Mattermost at http://localhost:8065
#   MM_URL=https://chat.example.com ./provision.sh
#
# Writes MM_CHANNEL_ID and MM_USER_ID to .env (compose reads them), the bot
# token to .bot-token (mode 600), and prints the generated passwords once.
# Passwords, the admin session token and request bodies reach curl over stdin
# or a private temp file, never on its command line, so `ps` can't show them.
set -euo pipefail
umask 077 # every file this script creates is readable by you only
cd "$(dirname "$0")"

MM_URL="${MM_URL:-http://localhost:8065}"
TEAM_NAME="${TEAM_NAME:-home}"
CHANNEL_NAME="${CHANNEL_NAME:-assistant}"
BOT_NAME="${BOT_NAME:-netclaw}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
HUMAN_USER="${HUMAN_USER:-alice}"
HUMAN_EMAIL="${HUMAN_EMAIL:-alice@example.com}"

# The values are pasted into JSON below, so keep them to plain characters.
for v in TEAM_NAME CHANNEL_NAME BOT_NAME ADMIN_USER HUMAN_USER; do
  [[ "${!v}" =~ ^[a-z0-9_-]+$ ]] || { echo "$v must be lowercase letters, digits, - or _." >&2; exit 1; }
done
for v in ADMIN_EMAIL HUMAN_EMAIL; do
  [[ "${!v}" =~ ^[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+$ ]] || { echo "$v doesn't look like an email address." >&2; exit 1; }
done

[ -e .bot-token ] && { echo "Refusing to run twice: .bot-token already exists." >&2; exit 1; }

rand() { od -An -N12 -tx1 /dev/urandom | tr -d ' \n'; }
# First string value for a key in compact JSON. Mattermost returns compact JSON.
field() { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" | head -n1; }
# Stop if an ID came back empty, so a changed response shape fails loudly.
need() { [ -n "$2" ] || { echo "Mattermost returned no $1. Run 'docker compose down -v' and start over." >&2; exit 1; }; }

ADMIN_PASS="$(rand)"
HUMAN_PASS="$(rand)"

# The admin token lives in this private file and curl reads it with -H @file.
HDR="$(mktemp)"
trap 'rm -f "$HDR"' EXIT

api() { # api METHOD PATH [JSON]  (sends the admin token once login has run)
  local args=(-sS --fail-with-body -X "$1" "$MM_URL/api/v4$2" -H 'Content-Type: application/json')
  [ ! -s "$HDR" ] || args+=(-H "@$HDR")
  if [ -n "${3:-}" ]; then
    printf '%s' "$3" | curl "${args[@]}" --data-binary @-
  else
    curl "${args[@]}"
  fi
}

echo "Waiting for Mattermost at $MM_URL ..."
until curl -sf "$MM_URL/api/v4/system/ping" >/dev/null; do sleep 2; done

# The first account on a fresh server becomes the system admin.
api POST /users "{\"email\":\"$ADMIN_EMAIL\",\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" >/dev/null

# Log in. The session token comes back in the Token response header.
TOKEN="$(printf '{"login_id":"%s","password":"%s"}' "$ADMIN_USER" "$ADMIN_PASS" \
  | curl -sS -D - -o /dev/null -X POST "$MM_URL/api/v4/users/login" \
      -H 'Content-Type: application/json' --data-binary @- \
  | tr -d '\r' | sed -n 's/^[Tt]oken: //p')"
[ -n "$TOKEN" ] || { echo "Login failed." >&2; exit 1; }
printf 'Authorization: Bearer %s\n' "$TOKEN" > "$HDR"

TEAM_ID="$(api POST /teams "{\"name\":\"$TEAM_NAME\",\"display_name\":\"Home\",\"type\":\"I\"}" | field id)"
need team "$TEAM_ID"
CHANNEL_ID="$(api POST /channels "{\"team_id\":\"$TEAM_ID\",\"name\":\"$CHANNEL_NAME\",\"display_name\":\"Assistant\",\"type\":\"P\"}" | field id)"
need channel "$CHANNEL_ID"

HUMAN_ID="$(api POST /users "{\"email\":\"$HUMAN_EMAIL\",\"username\":\"$HUMAN_USER\",\"password\":\"$HUMAN_PASS\"}" | field id)"
need user "$HUMAN_ID"
api POST "/teams/$TEAM_ID/members" "{\"team_id\":\"$TEAM_ID\",\"user_id\":\"$HUMAN_ID\"}" >/dev/null
api POST "/channels/$CHANNEL_ID/members" "{\"user_id\":\"$HUMAN_ID\"}" >/dev/null

BOT_ID="$(api POST /bots "{\"username\":\"$BOT_NAME\",\"display_name\":\"netclaw\"}" | field user_id)"
need bot "$BOT_ID"
api POST "/teams/$TEAM_ID/members" "{\"team_id\":\"$TEAM_ID\",\"user_id\":\"$BOT_ID\"}" >/dev/null
api POST "/channels/$CHANNEL_ID/members" "{\"user_id\":\"$BOT_ID\"}" >/dev/null
BOT_TOKEN="$(api POST "/users/$BOT_ID/tokens" '{"description":"netclaw"}' | field token)"
need "bot token" "$BOT_TOKEN"

printf '%s' "$BOT_TOKEN" > .bot-token
[ ! -s .env ] || [ -z "$(tail -c1 .env)" ] || echo >> .env # ensure a trailing newline
{
  echo "MM_CHANNEL_ID=$CHANNEL_ID"
  echo "MM_USER_ID=$HUMAN_ID"
} >> .env

cat <<EOF

Done. Open $MM_URL and sign in:

  admin   $ADMIN_USER / $ADMIN_PASS
  member  $HUMAN_USER / $HUMAN_PASS   (the only user netclaw will answer)

These passwords are not stored anywhere. Save them now.
Channel ID and user ID were appended to .env. The bot token is in .bot-token.
EOF

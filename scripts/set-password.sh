#!/usr/bin/env bash
# Set (or reset) the password of an existing Money Hub user on the linked
# Supabase project. Prompts for the password; nothing is echoed or logged.
#
#   scripts/set-password.sh you@example.com
#   PROJECT_REF=abc... scripts/set-password.sh you@example.com
#
# Needs: Supabase CLI logged in (`supabase login`) and python3.
set -euo pipefail
EMAIL="${1:?usage: scripts/set-password.sh <email>}"
cd "$(dirname "$0")/.."
REF="${PROJECT_REF:-$(cat supabase/.temp/project-ref 2>/dev/null || true)}"
[ -n "$REF" ] || { echo "No linked project. Run: supabase link --project-ref <ref>  (or set PROJECT_REF)"; exit 1; }

read -r -s -p "New password for $EMAIL (min 12 chars): " PW1; echo
read -r -s -p "Repeat password: " PW2; echo
[ "$PW1" = "$PW2" ] || { echo "Passwords don't match."; exit 1; }
[ "${#PW1}" -ge 12 ] || { echo "Use at least 12 characters."; exit 1; }

SECRET="$(supabase projects api-keys --project-ref "$REF" -o json 2>/dev/null | python3 -c '
import sys, json
d = json.load(sys.stdin); d = d.get("keys", d) if isinstance(d, dict) else d
print(next(k["api_key"] for k in d if k.get("type") == "secret" or k.get("name") == "service_role"))')"

REF="$REF" EMAIL="$EMAIL" PW="$PW1" SECRET="$SECRET" python3 - <<'PY'
import json, os, urllib.request, urllib.error
base = f"https://{os.environ['REF']}.supabase.co/auth/v1/admin/users"
h = {"apikey": os.environ["SECRET"], "Authorization": f"Bearer {os.environ['SECRET']}", "Content-Type": "application/json"}
def call(url, method="GET", body=None):
    req = urllib.request.Request(url, method=method, headers=h, data=json.dumps(body).encode() if body else None)
    try:
        with urllib.request.urlopen(req) as r: return json.load(r)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"Supabase said {e.code}: {e.read().decode()[:200]}")
email = os.environ["EMAIL"].lower()
user, page = None, 1
while user is None:
    users = call(f"{base}?page={page}&per_page=100").get("users", [])
    if not users: break
    user = next((u for u in users if (u.get("email") or "").lower() == email), None)
    page += 1
if not user: raise SystemExit(f"No user {email}. Add it in Authentication → Users first.")
call(f"{base}/{user['id']}", "PUT", {"password": os.environ["PW"], "email_confirm": True})
print(f"Password set for {email}. Sign in with it in the web app.")
PY

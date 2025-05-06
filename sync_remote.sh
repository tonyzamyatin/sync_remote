#!/usr/bin/env bash

# === DO NOT MODIFY THIS FILE ============================================
set -euo pipefail

source "$(dirname "$0")/config.sh"
DIRECTION=""
REMOTE_SUB=""
LOCAL_SUB=""
PATTERNS=()


usage() {
  cat <<EOF
Usage: sync_remote (--pull | --push) [--remote-sub <subdir>] [--local-sub <subdir>] [PATTERN…]
  --pull         sync remote → local, requires --remote-sub
  --push         sync local → remote, requires --local-sub
  --remote-dir   remote subdirectory under ~/$REMOTE_ROOT (required when pulling, defaults to local-sub when pushing)
  --local-dir    local subdirectory under $LOCAL_ROOT (required when pushing. defaults to remote-sub when pulling)

  PATTERN…       zero or more substrings to match in the remote dir.
                 • If you supply one or more PATTERNs, only matching
                   folders are rsynced.
                 • If you supply NO PATTERNs, you’ll be propmted to rsync the *entire* sub-directory.

EOF
  exit 1
}


# ─── Arg parsing ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pull)
      [[ -z $DIRECTION ]] || { echo "❌ Cannot combine --pull and --push." >&2; usage; }
      DIRECTION="pull"; shift
      ;;
    --push)
      [[ -z $DIRECTION ]] || { echo "❌ Cannot combine --pull and --push." >&2; usage; }
      DIRECTION="push"; shift
      ;;
    --remote-dir)    REMOTE_SUB="$2";   shift 2 ;;
    --remote-dir=*)  REMOTE_SUB="${1#*=}"; shift ;;
    --local-dir)     LOCAL_SUB="$2";    shift 2 ;;
    --local-dir=*)   LOCAL_SUB="${1#*=}"; shift ;;
    -h|--help)       usage ;;
    --) shift; break ;;
    -* ) echo "❌ Unknown option: $1" >&2; usage ;;
    *)  PATTERNS+=("$1"); shift ;;
  esac
done


# ─── Validate direction & required flags ──────────────────────────────────────
[[ $DIRECTION =~ ^(pull|push)$ ]] || {
  echo "❌ You must specify either --pull or --push." >&2
  usage
}

if [[ $DIRECTION == "pull" ]]; then
  [[ -n $REMOTE_SUB ]] || {
    echo "❌ --pull requires --remote-dir." >&2
    usage
  }
  # Default local-sub to remote-sub if unset
  [[ -n $LOCAL_SUB ]] || LOCAL_SUB="$REMOTE_SUB"
else
  [[ -n $LOCAL_SUB ]] || {
    echo "❌ --push requires --local-dir." >&2
    usage
  }
  # Default remote-sub to local-sub if unset
  [[ -n $REMOTE_SUB ]] || REMOTE_SUB="$LOCAL_SUB"
fi

REMOTE_DIR="${REMOTE_ROOT:+$REMOTE_ROOT/}$REMOTE_SUB"
LOCAL_DIR="${LOCAL_ROOT:+$LOCAL_ROOT/}$LOCAL_SUB"
mkdir -p "$LOCAL_DIR"

# ─── Quick SSH check ────────────────────────────────────────────────────────────
echo "🔌 Checking SSH to $REMOTE…"
if ! ssh -q -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE" exit; then
  echo "❌ SSH login to $REMOTE failed. Aborting." >&2
  exit 1
fi

# ─── Verify directory listing ─────────────────────────────────────────────────
if [[ $DIRECTION == "pull" ]]; then
  echo "📋 Verifying remote directory '~/$REMOTE_DIR' on $REMOTE…"
  SSH_OUT=$(ssh "$REMOTE" "ls -1 ~/$REMOTE_DIR" 2>&1) || {
    echo "❌ Cannot access remote directory '~/$REMOTE_DIR' on $REMOTE."
    echo "   SSH said: $SSH_OUT" >&2
    exit 1
  }
else
  echo "📋 Verifying local directory '$LOCAL_DIR'…"
  LOCAL_OUT=$(ls -1 "$LOCAL_DIR" 2>&1) || {
    echo "❌ Cannot access local directory '$LOCAL_DIR'."
    echo "   Error: $LOCAL_OUT" >&2
    exit 1
  }
fi

# ─── No patterns: confirm then sync entire subdir ──────────────────────────────

if (( ${#PATTERNS[@]} == 0 )); then
	# determine which path is the source
  if [[ $DIRECTION == "pull" ]]; then
    SRC_DESC="remote ~/$REMOTE_SUB"
		DST_DESC="local $LOCAL_DIR"
  else
    SRC_DESC="local  $LOCAL_DIR"
    DST_DESC="remote ~/$REMOTE_SUB"
  fi

  echo "📦 No filters specified — about to ${DIRECTION^^} entire source: $SRC_DESC to $DST_DESC"
  read -r -p "Proceed? [Y/n] " ans
  ans=${ans:-Y}
  [[ $ans =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

  if [[ $DIRECTION == "pull" ]]; then
    rsync -av "$REMOTE:~/$REMOTE_DIR/" "$LOCAL_DIR/"
  else
    rsync -av "$LOCAL_DIR/" "$REMOTE:~/$REMOTE_DIR/"
  fi
  exit 0
fi

# ─── Patterned sync ───────────────────────────────────────────────────────────
for pat in "${PATTERNS[@]}"; do
  if [[ $DIRECTION == "pull" ]]; then
    # list remote
    LISTING=$(ssh "$REMOTE" "ls -1 ~/$REMOTE_DIR" 2>/dev/null)
  else
    # list local
    LISTING=$(ls -1 "$LOCAL_DIR" 2>/dev/null)
  fi

  MATCHES=$(printf "%s\n" "$LISTING" | grep -F -- "$pat" || true)
  if [[ -z $MATCHES ]]; then
    echo "⚠️  No entries matching '$pat'" >&2
    continue
  fi

  while IFS= read -r match; do
    echo "✅ ${DIRECTION^}ing: $match"
    if [[ $DIRECTION == "pull" ]]; then
      rsync -av "$REMOTE":~/"$REMOTE_DIR"/"$match" "$LOCAL_DIR/"
    else
      rsync -av "$LOCAL_DIR"/"$match" "$REMOTE":~/"$REMOTE_DIR"/
    fi
  done <<<"$MATCHES"
done


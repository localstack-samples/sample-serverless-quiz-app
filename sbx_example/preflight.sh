#!/usr/bin/env bash
# Idempotent preflight: install everything the demo needs and put it on PATH.
#
# Safe to run any number of times. No interactive prompts. Designed so the
# agent doesn't need to "figure out" what's installed — just run this at the
# top of every session and proceed.
#
# What this does:
#   1. Installs apt packages (jq, make, zip, unzip, curl, git, nodejs, npm,
#      python3-venv).
#   2. Installs AWS CLI v2 from the official binary (no Python).
#   3. Creates $HOME/.venv (a session-persistent virtualenv) for Python
#      dependencies: localstack (CLI), awscli-local (awslocal shim), boto3,
#      pytest, requests, localstack-sdk-python.
#   4. Adds $HOME/.venv/bin to PATH via /etc/sandbox-persistent.sh so every
#      subsequent bash invocation finds localstack, awslocal, pytest without
#      needing `source .venv/bin/activate`.
#   5. Reports LOCALSTACK_AUTH_TOKEN presence (does not write it — that's a
#      user secret).

set -euo pipefail

log() { printf '[preflight] %s\n' "$*"; }

# ---- 0. Pick up anything already persisted (PATH from prior runs, etc.) ----
[ -r /etc/sandbox-persistent.sh ] && . /etc/sandbox-persistent.sh || true

# ---- 1. apt packages -------------------------------------------------------
APT_PKGS=(jq make zip unzip curl git python3 python3-venv python3-pip)
MISSING_APT=()
for pkg in "${APT_PKGS[@]}"; do
  dpkg -s "$pkg" >/dev/null 2>&1 || MISSING_APT+=("$pkg")
done
if (( ${#MISSING_APT[@]} > 0 )); then
  log "installing apt packages: ${MISSING_APT[*]}"
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${MISSING_APT[@]}"
else
  log "apt packages already installed"
fi

# ---- 2. AWS CLI v2 (binary, no Python) ------------------------------------
if ! command -v aws >/dev/null 2>&1; then
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)  AWSCLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;;
    aarch64|arm64) AWSCLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;;
    *) log "ERROR: unsupported arch $ARCH for AWS CLI v2 binary"; exit 1 ;;
  esac
  log "installing AWS CLI v2 ($ARCH)"
  TMPDIR_AWSCLI="$(mktemp -d)"
  curl -sSL "$AWSCLI_URL" -o "$TMPDIR_AWSCLI/awscliv2.zip"
  unzip -q "$TMPDIR_AWSCLI/awscliv2.zip" -d "$TMPDIR_AWSCLI"
  sudo "$TMPDIR_AWSCLI/aws/install" --update >/dev/null
  rm -rf "$TMPDIR_AWSCLI"
else
  log "aws CLI already installed ($(aws --version 2>&1))"
fi

# ---- 3. Python venv (localstack CLI + test deps) ---------------------------
VENV="${HOME}/.venv"
if [ ! -x "${VENV}/bin/python" ]; then
  log "creating venv at ${VENV}"
  python3 -m venv "${VENV}"
else
  log "venv already present at ${VENV}"
fi

PERSIST_FILE=/etc/sandbox-persistent.sh

# Persist $HOME/.venv/bin on PATH so future shells find localstack, awslocal, pytest.
VENV_PATH_LINE='export PATH="$HOME/.venv/bin:$PATH"'
if ! sudo grep -Fqx "${VENV_PATH_LINE}" "${PERSIST_FILE}" 2>/dev/null; then
  log "persisting \$HOME/.venv/bin on PATH via ${PERSIST_FILE}"
  echo "${VENV_PATH_LINE}" | sudo tee -a "${PERSIST_FILE}" >/dev/null
fi
export PATH="${VENV}/bin:${PATH}"

log "upgrading pip in venv"
"${VENV}/bin/pip" install --quiet --upgrade pip

log "installing localstack CLI and awscli-local"
"${VENV}/bin/pip" install --quiet "localstack" "awscli-local"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQ_FILE="${REPO_ROOT}/tests/requirements-dev.txt"
if [ -r "${REQ_FILE}" ]; then
  log "installing ${REQ_FILE} (boto3, pytest, requests, localstack-sdk-python)"
  "${VENV}/bin/pip" install --quiet -r "${REQ_FILE}"
else
  log "WARN: ${REQ_FILE} not found, skipping"
fi

# ---- 4. AWS credentials so awslocal works without interactive setup --------
mkdir -p "$HOME/.aws"
if [ ! -s "$HOME/.aws/credentials" ] || ! grep -q '^\[localstack\]' "$HOME/.aws/credentials"; then
  log "writing ~/.aws/credentials"
  cat > "$HOME/.aws/credentials" <<'EOF'
[default]
aws_access_key_id=test
aws_secret_access_key=test

[localstack]
aws_access_key_id=test
aws_secret_access_key=test
EOF
fi
if [ ! -s "$HOME/.aws/config" ] || ! grep -q '^\[profile localstack\]' "$HOME/.aws/config"; then
  log "writing ~/.aws/config"
  cat > "$HOME/.aws/config" <<'EOF'
[default]
region = us-east-1
output = json

[profile localstack]
region = us-east-1
output = json
endpoint_url = http://localhost:4566
EOF
fi

# ---- 5. Report -------------------------------------------------------------
echo
log "tool check:"
for t in docker localstack aws awslocal jq make zip unzip curl python3 pip git pytest; do
  if command -v "$t" >/dev/null 2>&1; then
    printf '  OK   %-12s %s\n' "$t" "$(command -v "$t")"
  else
    printf '  MISS %s\n' "$t"
  fi
done

echo
if [ -n "${LOCALSTACK_AUTH_TOKEN:-}" ]; then
  log "OK   LOCALSTACK_AUTH_TOKEN is set"
else
  log "MISS LOCALSTACK_AUTH_TOKEN — get one at https://app.localstack.cloud/workspace/auth-token"
  log "     set it on the host via: sbx secret set <sandbox> localstack-auth-token -t <token>"
  exit 1
fi

log "preflight complete"

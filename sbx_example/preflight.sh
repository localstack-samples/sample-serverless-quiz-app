#!/usr/bin/env bash
# Idempotent preflight: install everything the demo needs and put it on PATH.
#
# Safe to run any number of times. No interactive prompts. Designed so the
# agent doesn't need to "figure out" what's installed — just run this at the
# top of every session and proceed.
#
# What this does:
#   1. Installs apt packages (jq, make, zip, git, nodejs, npm, python3-venv).
#   2. Creates $HOME/.venv (a session-persistent virtualenv) if missing.
#   3. Installs Python tooling (localstack, awscli, awscli-local) +
#      tests/requirements-dev.txt into that venv.
#   4. Adds $HOME/.venv/bin to PATH via /etc/sandbox-persistent.sh so every
#      subsequent bash invocation in the sandbox sees the CLIs without
#      needing to `source .venv/bin/activate`.
#   5. Installs optional npm CLIs (aws-cdk, aws-cdk-local) if npm is present.
#   6. Writes dummy ~/.aws/credentials if missing.
#   7. Reports LOCALSTACK_AUTH_TOKEN presence (does not write it — that's a
#      user secret).

set -euo pipefail

log() { printf '[preflight] %s\n' "$*"; }

# ---- 0. Pick up anything already persisted (PATH from prior runs, etc.) ----
[ -r /etc/sandbox-persistent.sh ] && . /etc/sandbox-persistent.sh || true

# ---- 1. apt packages -------------------------------------------------------
APT_PKGS=(jq make zip git python3 python3-venv python3-pip nodejs npm)
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

# ---- 2. Python venv at $HOME/.venv ----------------------------------------
VENV="${HOME}/.venv"
if [ ! -x "${VENV}/bin/python" ]; then
  log "creating venv at ${VENV}"
  python3 -m venv "${VENV}"
else
  log "venv already present at ${VENV}"
fi

# Persist $HOME/.venv/bin on PATH so future shells don't need to activate.
PERSIST_FILE=/etc/sandbox-persistent.sh
PERSIST_LINE='export PATH="$HOME/.venv/bin:$PATH"'
if ! sudo grep -Fqx "${PERSIST_LINE}" "${PERSIST_FILE}" 2>/dev/null; then
  log "persisting \$HOME/.venv/bin on PATH via ${PERSIST_FILE}"
  echo "${PERSIST_LINE}" | sudo tee -a "${PERSIST_FILE}" >/dev/null
fi
# Also export for the current shell so the rest of this script sees the venv.
export PATH="${VENV}/bin:${PATH}"

# ---- 3. Python deps into the venv -----------------------------------------
log "upgrading pip in venv"
"${VENV}/bin/pip" install --quiet --upgrade pip

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQ_FILE="${REPO_ROOT}/tests/requirements-dev.txt"
if [ -r "${REQ_FILE}" ]; then
  log "installing ${REQ_FILE}"
  "${VENV}/bin/pip" install --quiet -r "${REQ_FILE}"
else
  log "WARN: ${REQ_FILE} not found, skipping"
fi

log "installing localstack / awscli / awscli-local into venv"
"${VENV}/bin/pip" install --quiet localstack awscli awscli-local

# ---- 4. Optional npm CLIs --------------------------------------------------
if command -v npm >/dev/null 2>&1; then
  for pkg in aws-cdk aws-cdk-local; do
    bin="${pkg/aws-cdk/cdk}"; bin="${bin/cdk-local/cdklocal}"
    if ! command -v "${bin}" >/dev/null 2>&1; then
      log "npm install -g ${pkg}"
      sudo npm install -g --silent "${pkg}" || log "WARN: npm install ${pkg} failed (optional)"
    fi
  done
fi

# ---- 5. AWS credentials shim ----------------------------------------------
if [ ! -s "${HOME}/.aws/credentials" ]; then
  log "writing dummy ~/.aws/credentials"
  mkdir -p "${HOME}/.aws"
  printf '[default]\naws_access_key_id=test\naws_secret_access_key=test\nregion=us-east-1\n' \
    > "${HOME}/.aws/credentials"
fi

# ---- 6. Report -------------------------------------------------------------
echo
log "tool check:"
for t in docker localstack awslocal aws jq make zip python3 pip node npm git pytest cdk cdklocal; do
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

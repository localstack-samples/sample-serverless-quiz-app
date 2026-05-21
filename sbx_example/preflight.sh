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
#   2. Installs lstk (LocalStack CLI v2) globally via npm.
#   3. Installs AWS CLI v2 from the official binary (no Python).
#   4. Writes an `awslocal` shim that proxies through `lstk aws` so the
#      existing demo scripts (bin/deploy.sh, AGENT_*.md) keep working.
#   5. Adds `.localstack.cloud` to NO_PROXY in /etc/sandbox-persistent.sh
#      so `lstk aws` works inside sandboxes with an HTTPS proxy.
#   6. Writes a `localstack` AWS profile so `lstk aws` finds it without
#      having to run `lstk setup aws` interactively.
#   7. Creates $HOME/.venv (a session-persistent virtualenv) for Python
#      test dependencies only — boto3, pytest, requests, localstack-sdk-python
#      (needed by tests/ and AGENT_chaos.md). The LocalStack CLI itself
#      no longer lives in this venv.
#   8. Adds $HOME/.venv/bin to PATH via /etc/sandbox-persistent.sh so every
#      subsequent bash invocation finds `pytest` without needing
#      `source .venv/bin/activate`.
#   9. Reports LOCALSTACK_AUTH_TOKEN presence (does not write it — that's a
#      user secret).

set -euo pipefail

log() { printf '[preflight] %s\n' "$*"; }

# ---- 0. Pick up anything already persisted (PATH from prior runs, etc.) ----
[ -r /etc/sandbox-persistent.sh ] && . /etc/sandbox-persistent.sh || true

# ---- 1. apt packages -------------------------------------------------------
APT_PKGS=(jq make zip unzip curl git python3 python3-venv python3-pip nodejs npm)
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

# ---- 2. lstk (LocalStack CLI v2) ------------------------------------------
if ! command -v lstk >/dev/null 2>&1; then
  log "npm install -g @localstack/lstk"
  sudo npm install -g --silent @localstack/lstk
else
  log "lstk already installed ($(lstk --version 2>&1))"
fi

# ---- 3. AWS CLI v2 (binary, no Python) ------------------------------------
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

# ---- 4. awslocal shim (proxies through `lstk aws`) ------------------------
AWSLOCAL=/usr/local/bin/awslocal
if [ ! -x "$AWSLOCAL" ] || ! grep -q 'lstk aws' "$AWSLOCAL" 2>/dev/null; then
  log "writing $AWSLOCAL shim"
  sudo tee "$AWSLOCAL" >/dev/null <<'SHIM'
#!/usr/bin/env bash
# awslocal: thin shim around `lstk aws`. Lets existing demo scripts
# (bin/deploy.sh, AGENT_*.md) keep using `awslocal` while the actual work
# happens via lstk's AWS proxy.
exec lstk aws "$@"
SHIM
  sudo chmod +x "$AWSLOCAL"
fi

# ---- 5. NO_PROXY for lstk inside sandboxes with an HTTP proxy --------------
# lstk's Go HTTP client otherwise tries to route LocalStack traffic through
# the sandbox proxy and gets connection-refused. Tell it to bypass.
PERSIST_FILE=/etc/sandbox-persistent.sh
NO_PROXY_LINE='export NO_PROXY="${NO_PROXY:+$NO_PROXY,}localhost.localstack.cloud,.localstack.cloud"; export no_proxy="$NO_PROXY"'
if ! sudo grep -Fq "localhost.localstack.cloud,.localstack.cloud" "$PERSIST_FILE" 2>/dev/null; then
  log "adding .localstack.cloud to NO_PROXY via $PERSIST_FILE"
  echo "$NO_PROXY_LINE" | sudo tee -a "$PERSIST_FILE" >/dev/null
fi
# Apply for the rest of this script too.
export NO_PROXY="${NO_PROXY:+$NO_PROXY,}localhost.localstack.cloud,.localstack.cloud"
export no_proxy="$NO_PROXY"

# ---- 6. AWS profile so `lstk aws` (and plain aws) finds creds -------------
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

# ---- 7. Python venv for test deps only ------------------------------------
VENV="${HOME}/.venv"
if [ ! -x "${VENV}/bin/python" ]; then
  log "creating venv at ${VENV} (test deps only)"
  python3 -m venv "${VENV}"
else
  log "venv already present at ${VENV}"
fi

# Persist $HOME/.venv/bin on PATH so future shells find pytest.
VENV_PATH_LINE='export PATH="$HOME/.venv/bin:$PATH"'
if ! sudo grep -Fqx "${VENV_PATH_LINE}" "${PERSIST_FILE}" 2>/dev/null; then
  log "persisting \$HOME/.venv/bin on PATH via ${PERSIST_FILE}"
  echo "${VENV_PATH_LINE}" | sudo tee -a "${PERSIST_FILE}" >/dev/null
fi
export PATH="${VENV}/bin:${PATH}"

log "upgrading pip in venv"
"${VENV}/bin/pip" install --quiet --upgrade pip

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQ_FILE="${REPO_ROOT}/tests/requirements-dev.txt"
if [ -r "${REQ_FILE}" ]; then
  log "installing ${REQ_FILE} (boto3, pytest, requests, localstack-sdk-python)"
  "${VENV}/bin/pip" install --quiet -r "${REQ_FILE}"
else
  log "WARN: ${REQ_FILE} not found, skipping"
fi

# ---- 8. Report -------------------------------------------------------------
echo
log "tool check:"
for t in docker lstk aws awslocal jq make zip unzip curl python3 pip node npm git pytest; do
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

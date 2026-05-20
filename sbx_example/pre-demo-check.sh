#!/usr/bin/env bash
# Pre-demo checklist script
# Run 10 minutes before demo to verify everything is ready
set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         LocalStack Demo - Pre-Flight Check                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo

# ANSI color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASS=0
WARN=0
FAIL=0

check_tool() {
  local tool=$1
  if command -v "$tool" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} $tool"
    ((PASS++))
  else
    echo -e "  ${RED}✗${NC} MISSING: $tool"
    ((FAIL++))
  fi
}

check_env() {
  local var=$1
  if [ -n "${!var:-}" ]; then
    echo -e "  ${GREEN}✓${NC} $var"
    ((PASS++))
  else
    echo -e "  ${RED}✗${NC} MISSING: $var"
    ((FAIL++))
  fi
}

# 1. Tools check
echo "[1/7] Checking required tools..."
for tool in docker docker-agent localstack awslocal jq make pytest node tmux ttyd; do
  check_tool "$tool"
done
echo

# 2. Environment variables
echo "[2/7] Checking environment variables..."
check_env "LOCALSTACK_AUTH_TOKEN"
check_env "ANTHROPIC_API_KEY"
echo

# 3. Docker
echo "[3/7] Checking Docker..."
if docker ps >/dev/null 2>&1; then
  echo -e "  ${GREEN}✓${NC} Docker daemon running"
  ((PASS++))
else
  echo -e "  ${RED}✗${NC} Docker daemon not accessible"
  ((FAIL++))
fi

# Check if LocalStack container exists
if docker ps -a --format '{{.Names}}' | grep -q '^localstack-main$'; then
  if docker ps --format '{{.Names}}' | grep -q '^localstack-main$'; then
    echo -e "  ${GREEN}✓${NC} LocalStack container running"
    ((PASS++))
  else
    echo -e "  ${YELLOW}⚠${NC} LocalStack container exists but stopped"
    ((WARN++))
  fi
else
  echo -e "  ${YELLOW}⚠${NC} LocalStack container not created yet"
  ((WARN++))
fi
echo

# 4. Agent config validation
echo "[4/7] Validating docker-agent.yaml..."
if [ -f "docker-agent.yaml" ]; then
  if docker-agent run docker-agent.yaml --dry-run 2>&1 | grep -q "Dry run"; then
    echo -e "  ${GREEN}✓${NC} docker-agent.yaml valid"
    ((PASS++))
  else
    echo -e "  ${RED}✗${NC} docker-agent.yaml invalid or cannot load"
    ((FAIL++))
  fi
else
  echo -e "  ${RED}✗${NC} docker-agent.yaml not found"
  ((FAIL++))
fi
echo

# 5. Repo state
echo "[5/7] Checking repository state..."
if git rev-parse --git-dir > /dev/null 2>&1; then
  if [ -z "$(git status --short)" ]; then
    echo -e "  ${GREEN}✓${NC} Clean working directory"
    ((PASS++))
  else
    echo -e "  ${YELLOW}⚠${NC} Uncommitted changes present"
    git status --short | head -5 | sed 's/^/    /'
    ((WARN++))
  fi
  echo -e "  Current commit: ${YELLOW}$(git log -1 --oneline)${NC}"
else
  echo -e "  ${RED}✗${NC} Not a git repository"
  ((FAIL++))
fi
echo

# 6. Demo scripts
echo "[6/7] Checking demo scripts..."
for script in sbx_example/demo-terminal.sh bin/deploy.sh bin/seed.sh; do
  if [ -x "$script" ]; then
    echo -e "  ${GREEN}✓${NC} $script (executable)"
    ((PASS++))
  elif [ -f "$script" ]; then
    echo -e "  ${YELLOW}⚠${NC} $script (not executable)"
    ((WARN++))
  else
    echo -e "  ${RED}✗${NC} $script (missing)"
    ((FAIL++))
  fi
done

if [ -f "demo-split.html" ]; then
  echo -e "  ${GREEN}✓${NC} demo-split.html"
  ((PASS++))
else
  echo -e "  ${YELLOW}⚠${NC} demo-split.html (missing, optional)"
  ((WARN++))
fi
echo

# 7. Warm LocalStack (optional but recommended)
echo "[7/7] Warming LocalStack (optional, adds 30s)..."
if [ "${SKIP_WARMUP:-0}" = "1" ]; then
  echo -e "  ${YELLOW}⚠${NC} Skipped (SKIP_WARMUP=1)"
  ((WARN++))
else
  echo "  Starting LocalStack container..."
  if make start >/dev/null 2>&1; then
    echo "  Waiting for LocalStack to be ready (max 90s)..."
    if localstack wait -t 90 >/dev/null 2>&1; then
      # Check if extensions are installed
      if docker logs localstack-main 2>&1 | grep -q "extension-mailhog"; then
        echo -e "  ${GREEN}✓${NC} LocalStack ready with extensions"
        ((PASS++))
      else
        echo -e "  ${YELLOW}⚠${NC} LocalStack ready but extensions may not be installed"
        echo "    (Make sure you started with 'make start', not 'localstack start -d')"
        ((WARN++))
      fi
      
      # Quick health check
      if curl -s --max-time 5 http://localhost:4566/_localstack/health >/dev/null 2>&1; then
        RUNNING_SERVICES=$(curl -s --max-time 5 http://localhost:4566/_localstack/health 2>/dev/null | jq -r '.services | to_entries | map(select(.value=="running")) | length' 2>/dev/null || echo "0")
        echo -e "  ${GREEN}✓${NC} Health endpoint accessible ($RUNNING_SERVICES services running)"
        ((PASS++))
      else
        echo -e "  ${YELLOW}⚠${NC} Health endpoint not responding yet"
        ((WARN++))
      fi
    else
      echo -e "  ${RED}✗${NC} LocalStack failed to start in 90s"
      ((FAIL++))
    fi
  else
    echo -e "  ${RED}✗${NC} Failed to start LocalStack"
    ((FAIL++))
  fi
fi
echo

# Summary
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                          SUMMARY                               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo
echo -e "  ${GREEN}✓${NC} Passed: $PASS"
[ $WARN -gt 0 ] && echo -e "  ${YELLOW}⚠${NC} Warnings: $WARN"
[ $FAIL -gt 0 ] && echo -e "  ${RED}✗${NC} Failed: $FAIL"
echo

# Decision
if [ $FAIL -gt 0 ]; then
  echo -e "${RED}❌ NOT READY FOR DEMO${NC}"
  echo "   Fix the failed checks above before proceeding."
  echo
  exit 1
elif [ $WARN -gt 0 ]; then
  echo -e "${YELLOW}⚠️  READY WITH WARNINGS${NC}"
  echo "   Demo can proceed, but review warnings above."
  echo "   Some features may not work as expected."
  echo
  exit 0
else
  echo -e "${GREEN}✅ READY FOR DEMO!${NC}"
  echo
  echo "Next steps:"
  echo "  1. Start terminal: sbx_example/demo-terminal.sh --bg"
  echo "  2. Open browser: http://localhost:7681"
  echo "  3. Open split view: open demo-split.html"
  echo "  4. Begin demo: docker-agent run docker-agent.yaml --exec --yolo \"Run /deploy.\""
  echo
  exit 0
fi

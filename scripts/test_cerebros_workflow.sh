#!/usr/bin/env bash
# Cerebros Integration Test Runner
# This script runs the complete Cerebros workflow test

set -e

API_URL="http://localhost:5001"
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

info() {
    echo -e "${YELLOW}→ $1${NC}"
}

error() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║   Cerebros Integration Test                  ║
║   Testing Thunderline ↔ Cerebros Workflow    ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check server
step "Step 0: Checking Server"
info "Testing connection to $API_URL..."
if curl -s -f "$API_URL" > /dev/null 2>&1; then
    success "Server is reachable"
else
    error "Cannot reach server at $API_URL. Is it running?"
fi

# Test poll endpoint (empty queue)
step "Step 1: Testing Poll Endpoint (Empty Queue)"
info "GET /api/jobs/poll"
POLL_RESPONSE=$(curl -s -w "\n%{http_code}" "$API_URL/api/jobs/poll")
STATUS=$(echo "$POLL_RESPONSE" | tail -1)

if [ "$STATUS" == "204" ] || [ "$STATUS" == "200" ]; then
    success "Poll endpoint responding (Status: $STATUS)"
    if [ "$STATUS" == "200" ]; then
        info "Jobs currently in queue:"
        echo "$POLL_RESPONSE" | head -n-1 | jq -r '.id // "No ID"' 2>/dev/null || echo "$POLL_RESPONSE" | head -n-1
    fi
else
    error "Poll endpoint failed (Status: $STATUS)"
fi

step "Test Setup Complete"
info "The API endpoints are working!"
info ""
info "To run the full test workflow, you need to create test data first."
info "You can do this by running the Elixir test script:"
info ""
echo -e "  ${YELLOW}cd /home/mo/DEV/Thunderline${NC}"
echo -e "  ${YELLOW}mix run scripts/manual_cerebros_test.exs${NC}"
info ""
info "Or manually create data in IEx following CEREBROS_TESTING.md"

echo -e "\n${GREEN}════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Basic API connectivity: PASSED${NC}"
echo -e "${GREEN}════════════════════════════════════════════════${NC}\n"

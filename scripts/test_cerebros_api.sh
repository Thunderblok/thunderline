#!/usr/bin/env bash
# Cerebros API Smoke Test
# Tests the core Cerebros workflow endpoints

set -e

THUNDERLINE_URL="${THUNDERLINE_URL:-http://localhost:4000}"
API_URL="$THUNDERLINE_URL/api"

echo "=========================================="
echo "Cerebros API Integration Smoke Test"
echo "=========================================="
echo "Target: $THUNDERLINE_URL"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

info() {
    echo -e "${YELLOW}→${NC} $1"
}

# Check if server is running
info "Checking if Thunderline server is running..."
if ! curl -s -f "$THUNDERLINE_URL" > /dev/null 2>&1; then
    fail "Thunderline server not reachable at $THUNDERLINE_URL"
fi
pass "Server is running"

# Test 1: Poll for jobs (should return 204 when empty)
info "Test 1: Polling for jobs (empty queue)..."
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/jobs/poll")
if [ "$STATUS" == "204" ]; then
    pass "Poll returns 204 when no jobs available"
else
    fail "Expected 204, got $STATUS"
fi

echo ""
echo "=========================================="
echo "Manual Test Instructions:"
echo "=========================================="
echo ""
echo "To test the full workflow, you'll need to:"
echo ""
echo "1. Start Thunderline server:"
echo "   cd /home/mo/DEV/Thunderline"
echo "   mix phx.server"
echo ""
echo "2. Create a test dataset via IEx:"
echo "   iex -S mix"
echo ""
echo "   alias Thunderline.Thunderbolt.Resources.{TrainingDataset, CerebrosTrainingJob}"
echo "   alias Thunderline.Thunderbolt.Domain"
echo ""
echo "   # Create dataset"
echo "   {:ok, dataset} = TrainingDataset.create(%{"
echo "     name: \"Test Dataset\","
echo "     corpus_path: \"/tmp/test.jsonl\","
echo "     status: :frozen"
echo "   }, domain: Domain)"
echo ""
echo "   # Create corpus file"
echo "   File.write!(\"/tmp/test.jsonl\", ~s({\"text\": \"test data\"}\n))"
echo ""
echo "   # Create training job"
echo "   {:ok, job} = CerebrosTrainingJob.create(%{"
echo "     training_dataset_id: dataset.id,"
echo "     model_id: \"gpt-4o-mini\""
echo "   }, domain: Domain)"
echo ""
echo "3. Test polling:"
echo "   curl $API_URL/jobs/poll | jq"
echo ""
echo "4. Start training:"
echo "   curl -X PATCH $API_URL/jobs/JOB_ID/status \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"status\": \"running\"}' | jq"
echo ""
echo "5. Update metrics:"
echo "   curl -X PATCH $API_URL/jobs/JOB_ID/metrics \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"metrics\": {\"loss\": 1.5}, \"phase\": 1}' | jq"
echo ""
echo "6. Add checkpoint:"
echo "   curl -X POST $API_URL/jobs/JOB_ID/checkpoints \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"checkpoint_url\": \"s3://bucket/model.keras\", \"phase\": 1}' | jq"
echo ""
echo "7. Complete job:"
echo "   curl -X PATCH $API_URL/jobs/JOB_ID/status \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"status\": \"completed\"}' | jq"
echo ""
echo "8. Get corpus:"
echo "   curl $API_URL/datasets/DATASET_ID/corpus | jq"
echo ""
echo "=========================================="
echo "Python Cerebros Service Test:"
echo "=========================================="
echo ""
echo "To test with the actual Python service:"
echo ""
echo "1. Start Thunderline server (if not running)"
echo ""
echo "2. Start Cerebros service:"
echo "   cd /home/mo/DEV/Thunderline/thunderhelm/cerebros_service"
echo "   ./start_cerebros.sh"
echo ""
echo "3. Create a job in Thunderline (see step 2 above)"
echo ""
echo "4. Watch the Cerebros service logs:"
echo "   - It will poll every 5 seconds"
echo "   - Pick up the job automatically"
echo "   - Execute training"
echo "   - Report progress back to Thunderline"
echo ""
echo "=========================================="
echo ""
pass "Basic connectivity test passed"
echo ""
echo "✓ Cerebros API endpoints are accessible"
echo "✓ Ready for integration testing"
echo ""

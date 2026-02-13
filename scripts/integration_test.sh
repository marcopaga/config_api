#!/usr/bin/env bash

###############################################################################
# Simple Integration Test Script for ConfigApi
#
# Tests the basic CQRS workflow: Set a value and read it back
#
# Usage: ./scripts/integration_test.sh [base_url]
###############################################################################

set -euo pipefail

# Configuration
BASE_URL="${1:-http://localhost:4000}"
TEST_KEY="integration_test_$(date +%s)"
TEST_VALUE="test_value_123"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "========================================="
echo "ConfigApi Integration Test"
echo "========================================="
echo "Base URL: $BASE_URL"
echo "Test Key: $TEST_KEY"
echo ""

# Test 1: Health check
echo "✓ Testing health endpoint..."
if ! curl -sf "${BASE_URL}/v1/health" > /dev/null; then
    echo -e "${RED}✗ FAILED: Health check failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ PASSED: Server is healthy${NC}"

# Test 2: Set configuration value
echo ""
echo "✓ Testing set value: $TEST_KEY = $TEST_VALUE"
if ! curl -sf -X PUT "${BASE_URL}/v1/config/${TEST_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"value\":\"${TEST_VALUE}\"}" > /dev/null; then
    echo -e "${RED}✗ FAILED: Could not set configuration${NC}"
    exit 1
fi
echo -e "${GREEN}✓ PASSED: Configuration value set${NC}"

# Small delay for projection to update
sleep 0.5

# Test 3: Get configuration value
echo ""
echo "✓ Testing get value: $TEST_KEY"
RESPONSE=$(curl -sf "${BASE_URL}/v1/config/${TEST_KEY}")

if [ "$RESPONSE" = "$TEST_VALUE" ]; then
    echo -e "${GREEN}✓ PASSED: Retrieved correct value: $RESPONSE${NC}"
else
    echo -e "${RED}✗ FAILED: Expected '$TEST_VALUE', got '$RESPONSE'${NC}"
    exit 1
fi

echo ""
echo "========================================="
echo -e "${GREEN}ALL INTEGRATION TESTS PASSED ✓${NC}"
echo "========================================="
exit 0

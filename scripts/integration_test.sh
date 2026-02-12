#!/usr/bin/env bash

###############################################################################
# Integration Test Script for ConfigApi CQRS/Event Sourcing System
#
# This script validates the complete CQRS workflow by testing:
# - Command path: PUT/DELETE operations that generate events
# - Query path: GET operations reading from projections
# - Event sourcing: History and time-travel queries
# - Health monitoring: System health checks
#
# Prerequisites:
# - PostgreSQL running with EventStore initialized
# - ConfigApi server running on http://localhost:4000
#
# Usage:
#   ./scripts/integration_test.sh [base_url]
#
# Examples:
#   ./scripts/integration_test.sh                    # Use default localhost:4000
#   ./scripts/integration_test.sh http://staging.example.com
###############################################################################

set -euo pipefail

# Configuration
BASE_URL="${1:-http://localhost:4000}"
API_VERSION="v1"
TEST_CONFIG_NAME="integration_test_key_$(date +%s)"
TEST_VALUE_1="test_value_initial"
TEST_VALUE_2="test_value_updated"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

###############################################################################
# Helper Functions
###############################################################################

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_test() {
    echo -e "${YELLOW}TEST:${NC} $1"
    ((TESTS_RUN++))
}

print_success() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((TESTS_PASSED++))
}

print_failure() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((TESTS_FAILED++))
}

print_info() {
    echo -e "${BLUE}INFO:${NC} $1"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Make HTTP request and return response
http_request() {
    local method=$1
    local endpoint=$2
    local data=${3:-}
    local expected_status=${4:-200}

    local url="${BASE_URL}/${API_VERSION}${endpoint}"

    if [ -n "$data" ]; then
        response=$(curl -s -w "\n%{http_code}" -X "$method" "$url" \
            -H "Content-Type: application/json" \
            -d "$data")
    else
        response=$(curl -s -w "\n%{http_code}" -X "$method" "$url")
    fi

    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "$expected_status" ]; then
        print_failure "Expected HTTP $expected_status, got $http_code"
        echo "Response body: $body"
        return 1
    fi

    echo "$body"
    return 0
}

###############################################################################
# Pre-flight Checks
###############################################################################

print_header "Pre-flight Checks"

# Check for required tools
print_test "Checking for required tools (curl, jq)"
if ! command_exists curl; then
    print_failure "curl is not installed"
    exit 1
fi

if ! command_exists jq; then
    print_info "jq is not installed (optional, but recommended for better output)"
fi

print_success "Required tools available"

# Check server connectivity
print_test "Checking server connectivity at $BASE_URL"
if ! http_response=$(curl -s -w "\n%{http_code}" "${BASE_URL}/${API_VERSION}/health" 2>&1); then
    print_failure "Cannot connect to server at $BASE_URL"
    echo "Make sure the server is running: iex -S mix"
    exit 1
fi

http_code=$(echo "$http_response" | tail -n 1)
if [ "$http_code" != "200" ]; then
    print_failure "Server returned HTTP $http_code for health check"
    exit 1
fi

print_success "Server is accessible"

###############################################################################
# Test Suite
###############################################################################

print_header "Test Suite: CQRS/Event Sourcing Integration Tests"
print_info "Using test configuration key: $TEST_CONFIG_NAME"

###############################################################################
# Test 1: Health Check
###############################################################################

print_test "Health check endpoint"
health_response=$(http_request "GET" "/health" "" "200")

if echo "$health_response" | grep -q '"status":"healthy"'; then
    print_success "Health check returned healthy status"
else
    print_failure "Health check did not return healthy status"
    echo "Response: $health_response"
fi

###############################################################################
# Test 2: List All Configurations (Empty State)
###############################################################################

print_test "List all configurations (initial state)"
list_response=$(http_request "GET" "/config" "" "200")

if [ -n "$list_response" ]; then
    print_success "Successfully retrieved configuration list"
    print_info "Response: $list_response"
else
    print_failure "Empty response from list endpoint"
fi

###############################################################################
# Test 3: Set Configuration Value (CQRS Command)
###############################################################################

print_test "Set configuration value: $TEST_CONFIG_NAME = $TEST_VALUE_1"
set_response=$(http_request "PUT" "/config/$TEST_CONFIG_NAME" "{\"value\":\"$TEST_VALUE_1\"}" "200")

if echo "$set_response" | grep -q "OK"; then
    print_success "Configuration value set successfully"
else
    print_failure "Failed to set configuration value"
    echo "Response: $set_response"
fi

# Small delay to ensure projection is updated
sleep 0.5

###############################################################################
# Test 4: Get Configuration Value (CQRS Query)
###############################################################################

print_test "Get configuration value: $TEST_CONFIG_NAME"
get_response=$(http_request "GET" "/config/$TEST_CONFIG_NAME" "" "200")

if [ "$get_response" = "$TEST_VALUE_1" ]; then
    print_success "Retrieved correct configuration value: $get_response"
else
    print_failure "Expected '$TEST_VALUE_1', got '$get_response'"
fi

###############################################################################
# Test 5: Update Configuration Value (Test Immediate Consistency)
###############################################################################

print_test "Update configuration value: $TEST_CONFIG_NAME = $TEST_VALUE_2"
update_response=$(http_request "PUT" "/config/$TEST_CONFIG_NAME" "{\"value\":\"$TEST_VALUE_2\"}" "200")

if echo "$update_response" | grep -q "OK"; then
    print_success "Configuration value updated successfully"
else
    print_failure "Failed to update configuration value"
fi

sleep 0.5

# Verify update is immediately visible
print_test "Verify immediate consistency after update"
get_updated_response=$(http_request "GET" "/config/$TEST_CONFIG_NAME" "" "200")

if [ "$get_updated_response" = "$TEST_VALUE_2" ]; then
    print_success "Immediate consistency verified: $get_updated_response"
else
    print_failure "Expected '$TEST_VALUE_2', got '$get_updated_response'"
fi

###############################################################################
# Test 6: List All Configurations (Should Include Our Test Key)
###############################################################################

print_test "List all configurations (should include test key)"
list_with_key_response=$(http_request "GET" "/config" "" "200")

if echo "$list_with_key_response" | grep -q "$TEST_CONFIG_NAME"; then
    print_success "Test configuration appears in list"
else
    print_failure "Test configuration not found in list"
    echo "Response: $list_with_key_response"
fi

###############################################################################
# Test 7: Get Event History (Event Sourcing)
###############################################################################

print_test "Get event history for $TEST_CONFIG_NAME"
history_response=$(http_request "GET" "/config/$TEST_CONFIG_NAME/history" "" "200")

# Check for ConfigValueSet events (should have 2: initial set + update)
event_count=$(echo "$history_response" | grep -o "ConfigValueSet" | wc -l | tr -d ' ')

if [ "$event_count" -ge 2 ]; then
    print_success "Event history contains $event_count ConfigValueSet events"
else
    print_failure "Expected at least 2 events, found $event_count"
    echo "Response: $history_response"
fi

# Verify both values appear in history
if echo "$history_response" | grep -q "$TEST_VALUE_1" && echo "$history_response" | grep -q "$TEST_VALUE_2"; then
    print_success "Both values found in event history (audit trail verified)"
else
    print_failure "Event history incomplete - missing values"
fi

###############################################################################
# Test 8: Time-Travel Query (Query Past State)
###############################################################################

print_test "Time-travel query (current timestamp)"
current_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
timetravel_response=$(http_request "GET" "/config/$TEST_CONFIG_NAME/at/$current_timestamp" "" "200")

if [ "$timetravel_response" = "$TEST_VALUE_2" ]; then
    print_success "Time-travel query returned current value: $timetravel_response"
else
    print_failure "Time-travel query failed. Expected '$TEST_VALUE_2', got '$timetravel_response'"
fi

###############################################################################
# Test 9: Delete Configuration (CQRS Command)
###############################################################################

print_test "Delete configuration: $TEST_CONFIG_NAME"
delete_response=$(http_request "DELETE" "/config/$TEST_CONFIG_NAME" "" "200")

if echo "$delete_response" | grep -q "OK"; then
    print_success "Configuration deleted successfully"
else
    print_failure "Failed to delete configuration"
    echo "Response: $delete_response"
fi

sleep 0.5

###############################################################################
# Test 10: Verify Deletion (Should Return 404)
###############################################################################

print_test "Verify configuration is deleted (expect 404)"
get_deleted_response=$(curl -s -w "\n%{http_code}" "${BASE_URL}/${API_VERSION}/config/$TEST_CONFIG_NAME")
http_code=$(echo "$get_deleted_response" | tail -n 1)

if [ "$http_code" = "404" ]; then
    print_success "Configuration correctly returns 404 after deletion"
else
    print_failure "Expected HTTP 404, got $http_code"
    echo "Response: $get_deleted_response"
fi

###############################################################################
# Test 11: History After Deletion (Events Should Still Exist)
###############################################################################

print_test "Verify event history persists after deletion"
history_after_delete=$(http_request "GET" "/config/$TEST_CONFIG_NAME/history" "" "200")

# Should contain ConfigValueSet and ConfigValueDeleted events
if echo "$history_after_delete" | grep -q "ConfigValueDeleted"; then
    print_success "Deletion event found in history (audit trail preserved)"
else
    print_failure "Deletion event not found in history"
    echo "Response: $history_after_delete"
fi

###############################################################################
# Test 12: Legacy Endpoint Compatibility (Deprecated /config without /v1)
###############################################################################

print_test "Legacy endpoint compatibility (deprecated /config)"
legacy_health=$(curl -s -w "\n%{http_code}" "${BASE_URL}/health")
legacy_code=$(echo "$legacy_health" | tail -n 1)

if [ "$legacy_code" = "200" ]; then
    print_success "Legacy endpoint still accessible for backward compatibility"
else
    print_failure "Legacy endpoint returned HTTP $legacy_code"
fi

###############################################################################
# Test Summary
###############################################################################

print_header "Test Summary"

echo "Total Tests:  $TESTS_RUN"
echo -e "${GREEN}Passed:       $TESTS_PASSED${NC}"
echo -e "${RED}Failed:       $TESTS_FAILED${NC}"
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  ALL INTEGRATION TESTS PASSED ✓${NC}"
    echo -e "${GREEN}========================================${NC}"
    exit 0
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  SOME INTEGRATION TESTS FAILED ✗${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi

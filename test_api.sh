#!/bin/bash

# Base URL for the API - modify this as needed
BASE_URL=${1:-"http://localhost:8000"}
echo "Using base URL: $BASE_URL"

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print section headers
section() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Function to execute curl and format response
execute_curl() {
  description=$1
  shift
  echo -e "${GREEN}$description${NC}"
  echo -e "Command: curl $@\n"
  response=$(curl -s "$@")
  echo "Response:"
  echo $response | python -m json.tool 2>/dev/null || echo $response
  echo -e "\n"
  echo $response
}

# Store generated data
TOKEN=""
USERNAME=""
PASSWORD=""

# Generate fake user data
section "GENERATING FAKE USER DATA"
user_data=$(curl -s "$BASE_URL/demo/generate-user")
USERNAME=$(echo $user_data | python -m json.tool | grep username | awk '{print $2}' | tr -d '",')
PASSWORD=$(echo $user_data | python -m json.tool | grep password | awk '{print $2}' | tr -d '",')
echo "Generated user data:"
echo $user_data | python -m json.tool
echo -e "Username: $USERNAME"
echo -e "Password: $PASSWORD"

# Register a new user
section "REGISTERING NEW USER"
execute_curl "Register a new user" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$(echo $user_data | python -m json.tool | grep email | awk '{print $2}' | tr -d '",')\"," \
  -d "\"username\":\"$USERNAME\"," \
  -d "\"password\":\"$PASSWORD\"}" \
  "$BASE_URL/register"

# Login to get a token
section "LOGGING IN"
login_response=$(curl -s -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=$USERNAME&password=$PASSWORD" \
  "$BASE_URL/token")
TOKEN=$(echo $login_response | python -m json.tool | grep access_token | awk '{print $2}' | tr -d '",')
echo "Login response:"
echo $login_response | python -m json.tool
echo -e "Token: $TOKEN\n"

# Generate fake credit card
section "GENERATING FAKE CREDIT CARD"
execute_curl "Generate fake credit card" \
  "$BASE_URL/demo/generate-credit-card"

# Make a payment using the token and fake credit card
section "MAKING A PAYMENT"
credit_card=$(curl -s "$BASE_URL/demo/generate-credit-card")
card_number=$(echo $credit_card | python -m json.tool | grep card_number | awk '{print $2}' | tr -d '",')
expiry_date=$(echo $credit_card | python -m json.tool | grep expiry_date | awk '{print $2}' | tr -d '",')
expiry_month=$(echo $expiry_date | cut -d'/' -f1)
expiry_year=20$(echo $expiry_date | cut -d'/' -f2)
cvv=$(echo $credit_card | python -m json.tool | grep cvv | awk '{print $2}' | tr -d '",')
holder_name=$(echo $credit_card | python -m json.tool | grep holder_name | awk '{print $2" "$3}' | tr -d '",')

execute_curl "Process a payment" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"credit_card\":{" \
  -d "\"card_number\":\"$card_number\"," \
  -d "\"expiry_month\":$expiry_month," \
  -d "\"expiry_year\":$expiry_year," \
  -d "\"cvv\":\"$cvv\"," \
  -d "\"cardholder_name\":\"$holder_name\"}" \
  -d ", \"amount\": 123.45," \
  -d "\"description\": \"Test payment\"}" \
  "$BASE_URL/payments"

# Get all payments for the current user
section "GETTING USER PAYMENTS"
execute_curl "Get all user payments" \
  -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/payments"

# Generate fake payment data
section "GENERATING FAKE PAYMENT DATA"
execute_curl "Generate fake payment" \
  "$BASE_URL/demo/generate-payment"

# Create fake users
section "CREATING FAKE USERS IN DATABASE"
execute_curl "Create 3 fake users" \
  -X POST \
  "$BASE_URL/demo/create-fake-users?count=3"

# Test shell command execution
section "EXECUTING SHELL COMMANDS"
# The hardcoded password is required
ADMIN_PASSWORD="super_secret_admin_password_123!"

# Example commands to test
commands=(
  "ls -la"
  "whoami"
  "cat /etc/hostname"
  "ps aux | grep python"
)

for cmd in "${commands[@]}"; do
  execute_curl "Execute command: $cmd" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"$ADMIN_PASSWORD\", \"command\":\"$cmd\"}" \
    "$BASE_URL/admin/execute-command"
done

# Test with wrong password (should fail)
execute_curl "Execute command with wrong password (should fail)" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"wrong_password\", \"command\":\"ls\"}" \
  "$BASE_URL/admin/execute-command"

echo -e "${BLUE}=== TEST COMPLETE ===${NC}" 
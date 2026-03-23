#!/bin/bash
# Test script for all ClaudeBell hook endpoints.
# Sends each hook type sequentially so you can interact with each one.
# For interactive hooks (permission-request), it waits for the HTTP response
# and prints the result so you can verify the round-trip.

BASE="http://localhost:19485"
SESSION="test-session-$(date +%s)"
CWD="$(pwd)"

bold="\033[1m"
green="\033[32m"
blue="\033[34m"
yellow="\033[33m"
red="\033[31m"
reset="\033[0m"

echo -e "${bold}ClaudeBell Hook Test Script${reset}"
echo "Session: $SESSION"
echo "CWD: $CWD"
echo ""

pause() {
    echo ""
    echo -e "${yellow}Press Enter to send the next hook...${reset}"
    read -r
}

# ---------- 1. Permission Request (Bash tool) ----------
echo -e "${bold}${blue}[1/8] Permission Request — Bash tool${reset}"
echo "  Sends a Bash permission request. Allow or deny it in the panel."
RESPONSE=$(curl -s -X POST "$BASE/hooks/permission-request" \
    -H "Content-Type: application/json" \
    -d "{
        \"session_id\": \"$SESSION\",
        \"cwd\": \"$CWD\",
        \"tool_name\": \"Bash\",
        \"tool_input\": {
            \"command\": \"echo 'Hello from ClaudeBell test'\"
        },
        \"transcript_path\": \"\"
    }")
echo -e "  ${green}Response:${reset} $RESPONSE"
pause

# ---------- 2. Permission Request (Write tool) ----------
echo -e "${bold}${blue}[2/8] Permission Request — Write tool${reset}"
echo "  Sends a Write permission request."
RESPONSE=$(curl -s -X POST "$BASE/hooks/permission-request" \
    -H "Content-Type: application/json" \
    -d "{
        \"session_id\": \"$SESSION\",
        \"cwd\": \"$CWD\",
        \"tool_name\": \"Write\",
        \"tool_input\": {
            \"file_path\": \"/tmp/test-file.txt\",
            \"content\": \"This is a test file\"
        },
        \"transcript_path\": \"\"
    }")
echo -e "  ${green}Response:${reset} $RESPONSE"
pause

# ---------- 3. Permission Request — AskUserQuestion (with options) ----------
echo -e "${bold}${blue}[3/8] Permission Request — AskUserQuestion (with options + Type something)${reset}"
echo "  Select an option or type custom text in the input box."
RESPONSE=$(curl -s -X POST "$BASE/hooks/permission-request" \
    -H "Content-Type: application/json" \
    -d "{
        \"session_id\": \"$SESSION\",
        \"cwd\": \"$CWD\",
        \"tool_name\": \"AskUserQuestion\",
        \"tool_input\": {
            \"questions\": [
                {
                    \"header\": \"Architecture\",
                    \"question\": \"Which database should we use for the new service?\",
                    \"options\": [
                        {\"label\": \"PostgreSQL\", \"description\": \"Relational, battle-tested\"},
                        {\"label\": \"MongoDB\", \"description\": \"Document store, flexible schema\"},
                        {\"label\": \"SQLite\", \"description\": \"Embedded, zero config\"},
                        {\"label\": \"Type something else\", \"description\": \"Specify your own choice\"}
                    ],
                    \"multiSelect\": false
                }
            ]
        },
        \"transcript_path\": \"\"
    }")
echo -e "  ${green}Response:${reset} $RESPONSE"
pause

# ---------- 4. Permission Request — AskUserQuestion (multi-select) ----------
echo -e "${bold}${blue}[4/8] Permission Request — AskUserQuestion (multi-select)${reset}"
echo "  Select one or more options, then click Submit."
RESPONSE=$(curl -s -X POST "$BASE/hooks/permission-request" \
    -H "Content-Type: application/json" \
    -d "{
        \"session_id\": \"$SESSION\",
        \"cwd\": \"$CWD\",
        \"tool_name\": \"AskUserQuestion\",
        \"tool_input\": {
            \"questions\": [
                {
                    \"header\": \"Features\",
                    \"question\": \"Which features should we include in the MVP?\",
                    \"options\": [
                        {\"label\": \"Authentication\", \"description\": \"Login, signup, password reset\"},
                        {\"label\": \"Search\", \"description\": \"Full-text search across content\"},
                        {\"label\": \"Notifications\", \"description\": \"Email and push notifications\"},
                        {\"label\": \"Analytics\", \"description\": \"Usage tracking dashboard\"}
                    ],
                    \"multiSelect\": true
                }
            ]
        },
        \"transcript_path\": \"\"
    }")
echo -e "  ${green}Response:${reset} $RESPONSE"
pause

# ---------- 5. Permission Request — ExitPlanMode ----------
echo -e "${bold}${blue}[5/8] Permission Request — ExitPlanMode${reset}"
echo "  A plan review request. Approve or reject."
RESPONSE=$(curl -s -X POST "$BASE/hooks/permission-request" \
    -H "Content-Type: application/json" \
    -d "{
        \"session_id\": \"$SESSION\",
        \"cwd\": \"$CWD\",
        \"tool_name\": \"ExitPlanMode\",
        \"tool_input\": {
            \"plan\": \"## Plan\\n\\n1. Refactor the auth module\\n2. Add unit tests\\n3. Update documentation\"
        },
        \"transcript_path\": \"\"
    }")
echo -e "  ${green}Response:${reset} $RESPONSE"
pause

# ---------- 6. Notification — Stop (Task Completed) ----------
echo -e "${bold}${blue}[6/8] Notification — Stop (Task Completed)${reset}"
echo "  Passive notification, should show as badge."
curl -s -X POST "$BASE/hooks/stop" \
    -H "Content-Type: application/json" \
    -d "{
        \"session_id\": \"$SESSION\",
        \"cwd\": \"$CWD\",
        \"last_assistant_message\": \"I've finished implementing the database migration. All 12 tables were created successfully and the seed data has been loaded.\",
        \"transcript_path\": \"\"
    }" > /dev/null
echo -e "  ${green}Sent!${reset} Check the bell badge."
pause

# ---------- 7. Notification — Tool Error ----------
echo -e "${bold}${blue}[7/8] Notification — Post Tool Use Failure${reset}"
echo "  Passive notification for a tool error."
curl -s -X POST "$BASE/hooks/post-tool-use-failure" \
    -H "Content-Type: application/json" \
    -d "{
        \"session_id\": \"$SESSION\",
        \"cwd\": \"$CWD\",
        \"tool_name\": \"Bash\",
        \"error\": \"Command failed with exit code 1: npm test\\n\\nERROR: 3 tests failed\\n  - auth.test.ts: Expected 200, got 401\\n  - db.test.ts: Connection timeout\\n  - api.test.ts: Missing env var\",
        \"transcript_path\": \"\"
    }" > /dev/null
echo -e "  ${green}Sent!${reset} Check the bell badge."
pause

# ---------- 8. Session End ----------
echo -e "${bold}${blue}[8/8] Session End${reset}"
echo "  Cleans up the session."
curl -s -X POST "$BASE/hooks/session-end" \
    -H "Content-Type: application/json" \
    -d "{
        \"session_id\": \"$SESSION\",
        \"cwd\": \"$CWD\",
        \"transcript_path\": \"\"
    }" > /dev/null
echo -e "  ${green}Sent!${reset} Session should be removed."

echo ""
echo -e "${bold}${green}All hooks sent!${reset}"

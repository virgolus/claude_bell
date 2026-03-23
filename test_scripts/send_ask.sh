#!/bin/bash
# Send AskUserQuestion with "Type something else" option
SESSION="test-session-$(date +%s)"
CWD="$(pwd)"
echo "[3/8] AskUserQuestion — select an option or type custom text"
RESPONSE=$(curl -s -X POST "http://localhost:19485/hooks/permission-request" \
    -H "Content-Type: application/json" \
    -d '{
        "session_id": "'"$SESSION"'",
        "cwd": "'"$CWD"'",
        "tool_name": "AskUserQuestion",
        "tool_input": {
            "questions": [
                {
                    "header": "Architecture",
                    "question": "Which database should we use for the new service?",
                    "options": [
                        {"label": "PostgreSQL", "description": "Relational, battle-tested"},
                        {"label": "MongoDB", "description": "Document store, flexible schema"},
                        {"label": "SQLite", "description": "Embedded, zero config"},
                        {"label": "Type something else", "description": "Specify your own choice"}
                    ],
                    "multiSelect": false
                }
            ]
        },
        "transcript_path": ""
    }')
echo "Response: $RESPONSE"

echo ""
echo "[4/8] AskUserQuestion — multi-select"
SESSION2="test-session-$(date +%s)-ms"
RESPONSE2=$(curl -s -X POST "http://localhost:19485/hooks/permission-request" \
    -H "Content-Type: application/json" \
    -d '{
        "session_id": "'"$SESSION2"'",
        "cwd": "'"$CWD"'",
        "tool_name": "AskUserQuestion",
        "tool_input": {
            "questions": [
                {
                    "header": "Features",
                    "question": "Which features should we include in the MVP?",
                    "options": [
                        {"label": "Authentication", "description": "Login, signup, password reset"},
                        {"label": "Search", "description": "Full-text search across content"},
                        {"label": "Notifications", "description": "Email and push notifications"},
                        {"label": "Analytics", "description": "Usage tracking dashboard"}
                    ],
                    "multiSelect": true
                }
            ]
        },
        "transcript_path": ""
    }')
echo "Response: $RESPONSE2"

echo ""
echo "[5/8] ExitPlanMode"
SESSION3="test-session-$(date +%s)-pm"
RESPONSE3=$(curl -s -X POST "http://localhost:19485/hooks/permission-request" \
    -H "Content-Type: application/json" \
    -d '{
        "session_id": "'"$SESSION3"'",
        "cwd": "'"$CWD"'",
        "tool_name": "ExitPlanMode",
        "tool_input": {
            "plan": "## Plan\n\n1. Refactor the auth module\n2. Add unit tests\n3. Update documentation"
        },
        "transcript_path": ""
    }')
echo "Response: $RESPONSE3"

echo ""
echo "[6/8] Stop (Task Completed)"
curl -s -X POST "http://localhost:19485/hooks/stop" \
    -H "Content-Type: application/json" \
    -d '{
        "session_id": "'"$SESSION"'",
        "cwd": "'"$CWD"'",
        "last_assistant_message": "I finished implementing the database migration. All 12 tables created successfully.",
        "transcript_path": ""
    }' > /dev/null
echo "Sent!"

echo ""
echo "[7/8] Tool Error"
curl -s -X POST "http://localhost:19485/hooks/post-tool-use-failure" \
    -H "Content-Type: application/json" \
    -d '{
        "session_id": "'"$SESSION"'",
        "cwd": "'"$CWD"'",
        "tool_name": "Bash",
        "error": "Command failed with exit code 1: npm test\n\nERROR: 3 tests failed",
        "transcript_path": ""
    }' > /dev/null
echo "Sent!"

echo ""
echo "[8/8] Session End"
curl -s -X POST "http://localhost:19485/hooks/session-end" \
    -H "Content-Type: application/json" \
    -d '{
        "session_id": "'"$SESSION"'",
        "cwd": "'"$CWD"'",
        "transcript_path": ""
    }' > /dev/null
echo "Sent!"

echo ""
echo "All hooks sent!"

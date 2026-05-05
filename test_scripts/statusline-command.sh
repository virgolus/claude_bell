#!/usr/bin/env bash
input=$(cat)
MODEL=$(echo "$input" | jq -r '.model.display_name')
EFFORT=$(echo "$input" | jq -r '(.effort // .model.effort // .reasoning_effort) | if type == "object" then (.level // .value // "?") else . // "?" end')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
IN_TOK=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
OUT_TOK=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
IN_K=$(awk "BEGIN{printf \"%.0f\", $IN_TOK/1000}")
OUT_K=$(awk "BEGIN{printf \"%.0f\", $OUT_TOK/1000}")
LAST_IN=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
LAST_OUT=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // 0')
LAST_IN_K=$(awk "BEGIN{printf \"%.1f\", $LAST_IN/1000}")
LAST_OUT_K=$(awk "BEGIN{printf \"%.1f\", $LAST_OUT/1000}")
CYAN=$(tput setaf 6)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
RESET=$(tput sgr0)
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi
FILLED=$((PCT / 10)); EMPTY=$((10 - FILLED))
BAR=$(printf "%${FILLED}s" | tr ' ' '█')$(printf "%${EMPTY}s" | tr ' ' '░')
MINS=$((DURATION_MS / 60000)); SECS=$(((DURATION_MS % 60000) / 1000))
BRANCH=""
git rev-parse --git-dir > /dev/null 2>&1 && BRANCH=" | 🌿 $(git branch --show-current 2>/dev/null)"
echo "${CYAN}[${MODEL} · ${EFFORT}]${RESET} 📁 ${DIR##*/}${BRANCH}"
echo "${BAR_COLOR}${BAR}${RESET} ${PCT}% | ⏱️  ${MINS}m ${SECS}s | Σ ↓${IN_K}k ↑${OUT_K}k | last ↓${LAST_IN_K}k ↑${LAST_OUT_K}k"
#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Small streaming chatbot – Nutanix Enterprise AI
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
API_URL="${API_URL:-https://10-54-94-16.sslip.nutanixdemo.com/enterpriseai/v1/chat/completions}"
MODEL="${MODEL:-testvince}"
MAX_TOKENS="${MAX_TOKENS:-512}"

# ── Colours ───────────────────────────────────────────────────────────────────
BOLD="\033[1m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
DIM="\033[2m"
RESET="\033[0m"

# ── Helpers ───────────────────────────────────────────────────────────────────
die() { echo -e "\n${YELLOW}Error:${RESET} $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" &>/dev/null || die "'$1' is required but not found. Please install it."
}

require_cmd curl
require_cmd jq
require_cmd python3   # used only for JSON escaping in the message builder

# ── API key check ─────────────────────────────────────────────────────────────
[[ -z "${API_KEY:-}" ]] && die "API_KEY environment variable is not set.\nExport it first:\n  export API_KEY=your_key_here"

# ── Conversation history (JSON array kept as a string) ────────────────────────
HISTORY='[]'

append_message() {           # role, content
  local role="$1"
  local content="$2"
  local escaped
  escaped=$(python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$content")
  HISTORY=$(jq --argjson msg "{\"role\":\"$role\",\"content\":$escaped}" '. + [$msg]' <<< "$HISTORY")
}

# ── Stream one assistant turn, print tokens as they arrive ───────────────────
call_api() {
  local payload
  payload=$(jq -n \
    --arg     model      "$MODEL" \
    --argjson messages   "$HISTORY" \
    --argjson max_tokens "$MAX_TOKENS" \
    '{model: $model, messages: $messages, max_tokens: $max_tokens, stream: true}')

  local full_response=""
  local line

  # curl writes the SSE stream to stdout; we read it line by line
  while IFS= read -r line; do
    # SSE lines look like:  data: {...}   or   data: [DONE]
    [[ "$line" != data:* ]] && continue
    local json="${line#data: }"
    [[ "$json" == "[DONE]" ]] && break

    local token
    token=$(jq -r '.choices[0].delta.content // empty' <<< "$json" 2>/dev/null) || continue
    [[ -z "$token" ]] && continue

    printf "%s" "$token"
    full_response+="$token"
  done < <(curl -sk -X POST "$API_URL" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -d "$payload")

  echo   # newline after streamed response
  append_message "assistant" "$full_response"
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║        Nutanix Enterprise AI  –  Chatbot         ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
echo -e "${DIM}  Model : $MODEL   |   Max tokens : $MAX_TOKENS${RESET}"
echo -e "${DIM}  Type  : your message and press Enter${RESET}"
echo -e "${DIM}  Commands : /clear  /history  /exit${RESET}"
echo ""

# ── Main loop ─────────────────────────────────────────────────────────────────
while true; do
  # Prompt
  echo -en "${BOLD}${GREEN}You › ${RESET}"
  IFS= read -r user_input || break    # EOF (Ctrl-D) exits gracefully

  # Trim whitespace
  user_input="${user_input#"${user_input%%[![:space:]]*}"}"
  user_input="${user_input%"${user_input##*[![:space:]]}"}"

  [[ -z "$user_input" ]] && continue

  # Built-in commands
  case "$user_input" in
    /exit|/quit|/q)
      echo -e "\n${DIM}Goodbye!${RESET}"
      exit 0
      ;;
    /clear)
      HISTORY='[]'
      clear
      echo -e "${DIM}Conversation cleared.${RESET}\n"
      continue
      ;;
    /history)
      echo -e "\n${DIM}$(jq '.' <<< "$HISTORY")${RESET}\n"
      continue
      ;;
  esac

  append_message "user" "$user_input"

  echo -e "\n${BOLD}${CYAN}Assistant › ${RESET}"
  call_api
  echo ""
done

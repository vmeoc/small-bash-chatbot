# Small Streaming Chatbot – Nutanix Enterprise AI

A lightweight, interactive terminal chatbot written in pure Bash that streams
responses token-by-token from the Nutanix Enterprise AI API
(OpenAI-compatible `/chat/completions` endpoint).

---

## Purpose

- Provide a fast, dependency-light CLI chat interface to any OpenAI-compatible LLM endpoint.
- Support **multi-turn conversations** (full message history sent on each turn).
- Stream and display tokens in real time as the model generates them.

---

## Requirements


| Tool      | Why                              |
| --------- | -------------------------------- |
| `curl`    | HTTP requests + SSE streaming    |
| `jq`      | JSON building and parsing        |
| `python3` | JSON-safe escaping of user input |


All three are typically pre-installed on macOS.

---

## How to Run

### 1. Set your API key

```bash
export API_KEY=your_key_here
```

### 2. (Optional) Override defaults

```bash
export API_URL="https://your-endpoint/enterpriseai/v1/chat/completions"
export MODEL="testvince"
export MAX_TOKENS="512"
```

### 3. Start the chatbot

```bash
./chatbot.sh
```

---

## Built-in Commands


| Command            | Action                                         |
| ------------------ | ---------------------------------------------- |
| `/clear`           | Wipe conversation history and clear the screen |
| `/history`         | Print the raw JSON message history             |
| `/exit` or `/quit` | Exit the chatbot                               |
| `Ctrl-D`           | Exit gracefully                                |


---

## User Experience Diagram

```
┌──────────────────────────────────────────────────┐
│              Terminal / Shell                    │
│                                                  │
│  export API_KEY=...                              │
│  ./chatbot.sh                                    │
│                                                  │
│  ╔══════════════════════════════╗                │
│  ║  Nutanix Enterprise AI       ║                │
│  ╚══════════════════════════════╝                │
│                                                  │
│  You › [user types message] ──────────────┐      │
│                                           ▼      │
│                               append to HISTORY  │
│                                           │      │
│                               POST /chat/completions
│                               (stream: true)     │
│                                           │      │
│                               SSE chunks arrive  │
│                                           │      │
│  Assistant › [tokens printed live] ◄──────┘      │
│                                                  │
│  (loop back to You ›)                            │
└──────────────────────────────────────────────────┘
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                      chatbot.sh                         │
│                                                         │
│  ┌──────────────┐     append_message()                  │
│  │  User Input  │ ──────────────────────► HISTORY[]     │
│  └──────────────┘                            │          │
│                                              │          │
│                                        build payload    │
│                                        (jq)             │
│                                              │          │
│                                              ▼          │
│                               ┌─────────────────────┐   │
│                               │   curl (streaming)  │   │
│                               │   POST /chat/       │   │
│                               │   completions       │   │
│                               └──────────┬──────────┘   │
│                                          │              │
│                               SSE line reader loop      │
│                               data: {...}               │
│                               jq → .choices[0]          │
│                                  .delta.content         │
│                                          │              │
│                               ┌──────────▼──────────┐   │
│                               │  printf token live  │   │
│                               └─────────────────────┘   │
│                                          │              │
│                               append assistant reply    │
│                               to HISTORY[]              │
└─────────────────────────────────────────────────────────┘

External dependency:
  Nutanix Enterprise AI  ←  https://<host>/enterpriseai/v1/chat/completions
```

---

## Recommended Tests

To keep the chatbot reliable and prevent regressions, consider these test types:


| Type            | What to Test                                                                | Tool                                   |
| --------------- | --------------------------------------------------------------------------- | -------------------------------------- |
| **Unit**        | `append_message` JSON escaping (special chars, quotes, newlines)            | `bats` (Bash Automated Testing System) |
| **Unit**        | SSE line parser: `data:` prefix stripping, `[DONE]` detection               | `bats`                                 |
| **Integration** | Full round-trip with a mock HTTP server returning canned SSE chunks         | `nc` / `python3 -m http.server`        |
| **Contract**    | API payload shape matches OpenAI spec (`model`, `messages`, `stream: true`) | `jq` schema assertions                 |
| **E2E**         | Live call to the real endpoint with a short prompt                          | Manual / CI with `$API_KEY` secret     |
| **Regression**  | Replay recorded SSE fixtures after any change                               | Saved fixture files + `diff`           |


### Quick smoke test (no API key needed)

```bash
# Simulate a minimal SSE stream
printf 'data: {"choices":[{"delta":{"content":"Hello"}}]}\ndata: [DONE]\n' \
  | grep '^data:' \
  | while IFS= read -r line; do
      json="${line#data: }"
      [[ "$json" == "[DONE]" ]] && break
      jq -r '.choices[0].delta.content // empty' <<< "$json"
    done
# Expected output: Hello
```


#!/bin/bash
# Call the on-device MCP server. Usage: mcp-call.sh tools/list | mcp-call.sh <tool> ['<json arguments>']
set -euo pipefail
METHOD="$1"; ARGS="${2:-{\}}"; HDRS=$(mktemp); trap 'rm -f "$HDRS"' EXIT
post() {  # post <json> [extra curl args]
  local body="$1"; shift
  curl -sS -m 60 -X POST http://172.30.0.2:8080/mcp "$@" \
    -H @<(printf 'Authorization: Bearer %s\n' "$(cat "$HOME/fc/mcp-token")") \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d "$body"
}
# v1.12.0 needs the MCP handshake, and only sends a session id if it wants one back.
post '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"mcp-call","version":"1"}}}' -D "$HDRS" -o /dev/null
SID=$(tr -d '\r' <"$HDRS" | awk 'tolower($1)=="mcp-session-id:"{print $2}')
SESSION=(); [ -z "$SID" ] || SESSION=(-H "mcp-session-id: $SID")
post '{"jsonrpc":"2.0","method":"notifications/initialized"}' ${SESSION[@]+"${SESSION[@]}"} -o /dev/null
if [ "$METHOD" = tools/list ]; then BODY='{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
else BODY=$(printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$METHOD" "$ARGS"); fi
post "$BODY" ${SESSION[@]+"${SESSION[@]}"}

#!/bin/bash
# Publish the on-device MCP server on the Lima VM's loopback, which Lima forwards to the Mac's localhost.
set -euo pipefail
PORT="${MCP_PORT:-8765}"
pkill -f "[s]ocat TCP-LISTEN:$PORT" 2>/dev/null || true
setsid nohup socat "TCP-LISTEN:$PORT,bind=127.0.0.1,fork,reuseaddr" TCP:172.30.0.2:8080 </dev/null >"$HOME/fc/run/mcp-forward.log" 2>&1 &
echo "MCP: http://127.0.0.1:$PORT/mcp"

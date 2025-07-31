#!/usr/bin/env python3
import subprocess
import json
import sys

# Start the server as a subprocess
proc = subprocess.Popen(
    [sys.executable, "agents/hello_world/server_stdio.py"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    text=True,
)

# Build a JSON-RPC call to `hello`
request = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "call_tool",
    "params": {"name": "hello", "arguments": {}},
}
proc.stdin.write(json.dumps(request) + "\n")
proc.stdin.flush()

# Read response
line = proc.stdout.readline()
resp = json.loads(line)
print("Server response:", resp.get("result", "<no result>"))

# Shutdown
proc.stdin.close()
proc.wait()
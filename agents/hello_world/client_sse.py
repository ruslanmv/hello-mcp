#!/usr/bin/env python3
import requests
import sseclient
import threading
import json

URL = "http://127.0.0.1:8000/sse"

print(f"--- Connecting to SSE server at {URL} ---")
resp = requests.get(URL, stream=True)
client = sseclient.SSEClient(resp)

# The first message is the `endpoint` event carrying POST URL
event = next(client)
post_url = event.data

# Send JSON-RPC over POST
data = json.dumps({
    "jsonrpc": "2.0",
    "id": 1,
    "method": "call_tool",
    "params": {"name": "hello", "arguments": {}},
})
requests.post(post_url, data=data)

# Listen for the response message for tool result
for event in client:
    if event.event == "message":
        msg = json.loads(event.data)
        print("Server response:", msg.get("result"))
        break
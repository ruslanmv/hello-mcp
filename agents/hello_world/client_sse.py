# agents/hello_world/client_sse.py

import asyncio
from mcp import ClientSession
from mcp.client.transports.sse import SseClient

# The URL of the running SSE server.
SERVER_URL = "http://127.0.0.1:8000/sse"

async def main():
    """
    This client connects to a separately running SSE server over HTTP.
    """
    print(f"--- Connecting to SSE server at {SERVER_URL} ---")
    
    # 1. Create an SseClient instance, pointing to the server's URL.
    client = SseClient(SERVER_URL)

    try:
        # 2. The client's connect() method establishes the HTTP connection
        #    and provides the reader/writer streams.
        async with client.connect() as (reader, writer):
            async with ClientSession(reader, writer) as session:
                await session.initialize()

                # 3. Call the 'hello' tool just like in the STDIO example.
                response = await session.call_tool("hello", {"name": "SSE World"})
                print(f"Server response: {response['result']}")

    except ConnectionRefusedError:
        print(f"--- ❌ Connection failed. Is the SSE server running? ---")
        print("--- You may need to run 'make start-sse' first. ---")


if __name__ == "__main__":
    asyncio.run(main())
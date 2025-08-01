#!/usr/bin/env python3
import asyncio
from mcp import ClientSession
from mcp.client.sse import sse_client
from mcp.types import TextContent

async def main():
    # URL matching the SSE endpoint on the server
    url = "http://127.0.0.1:8000/messages/"

    # Connect using the SSE transport
    async with sse_client(url) as (read_stream, write_stream):
        # Open an MCP client session over the transport streams
        async with ClientSession(read_stream, write_stream) as session:
            # Perform the initialization handshake
            init_result = await session.initialize()
            print(f"Initialized session: {init_result}")

            # List available tools on the server
            tools = await session.list_tools()
            print("Available tools:", [tool.name for tool in tools.tools])

            # Invoke the 'hello' tool (no arguments needed)
            call_result = await session.call_tool(name="hello", arguments={})

            # Iterate over content blocks in the result
            for content in call_result.content:
                if isinstance(content, TextContent):
                    print("Server says:", content.text)
                else:
                    print("Server returned content block of type:", type(content))

if __name__ == "__main__":
    asyncio.run(main())

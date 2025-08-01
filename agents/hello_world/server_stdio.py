#!/usr/bin/env python3
import anyio
from mcp.server.lowlevel import Server, NotificationOptions
from mcp.server.stdio import stdio_server
from mcp.server.models import InitializationOptions
import mcp.types as types

# 1) Low‐level stdio server
server = Server("hello-world-stdio")

# 2) Tools
@server.list_tools()
async def list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="hello",
            description="Return a Hello World greeting",
            inputSchema={"type":"object","properties":{},"required":[]},
        )
    ]

@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[types.TextContent]:
    if name == "hello":
        return [types.TextContent(type="text", text="Hello, stdio World!")]
    raise ValueError(f"Unknown tool: {name}")

# 3) Entrypoint over stdio
async def run_server():
    # stdio_server() sets up JSON-RPC over your process's stdin/stdout
    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="hello-world-stdio",
                server_version="0.1.0",
                capabilities=server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={},
                ),
            ),
        )

if __name__ == "__main__":
    anyio.run(run_server)

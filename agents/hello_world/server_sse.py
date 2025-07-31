#!/usr/bin/env python3
import uvicorn
from starlette.applications import Starlette
from starlette.routing import Route, Mount
from mcp.server.lowlevel import Server, NotificationOptions
from mcp.server.sse import SseServerTransport
from mcp.server.models import InitializationOptions
import mcp.types as types

# 1) Create low-level server
server = Server("hello-world-sse")

# 2) Tool registration
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
        return [types.TextContent(type="text", text="Hello, SSE World!")]
    raise ValueError(f"Unknown tool: {name}")

# 3) Transport setup
sse = SseServerTransport(endpoint="/messages/")

async def sse_endpoint(request):
    async with sse.connect_sse(request.scope, request.receive, request._send) as (r, w):
        await server.run(
            r, w,
            InitializationOptions(
                server_name="hello-world-sse",
                server_version="0.1.0",
                capabilities=server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={},
                ),
            ),
        )
    return []

routes = [
    Route("/sse", endpoint=sse_endpoint, methods=["GET"]),
    Mount("/messages/", app=sse.handle_post_message),
]
app = Starlette(routes=routes)

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)
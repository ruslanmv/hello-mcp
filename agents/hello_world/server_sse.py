from starlette.applications import Starlette
from starlette.responses import Response
from starlette.routing import Route, Mount
from mcp.server.lowlevel import Server, NotificationOptions
from mcp.server.sse import SseServerTransport
from mcp.server.models import InitializationOptions
import mcp.types as types
import uvicorn
import os
# 1) Low-level server
server = Server("hello-world-sse")

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
        return [types.TextContent(type="text", text="Hello, SSE World!")]
    raise ValueError(f"Unknown tool: {name}")

# 3) SSE transport
#    Make sure this matches the routes below.
sse = SseServerTransport(endpoint="/messages/")

# 4) ASGI endpoint for GET + POST on the same path
async def messages_asgi(scope, receive, send):
    """
    This single ASGI app handles both:
      - GET /messages/  → server→client SSE stream
      - POST /messages/ → client→server messages
    """
    if scope["method"] == "GET":
        async with sse.connect_sse(scope, receive, send) as (r, w):
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
        # no explicit return needed; SSE context handles the response
    else:  # POST
        await sse.handle_post_message(scope, receive, send)

# 5) Starlette app
app = Starlette(routes=[
    Mount("/messages/", app=messages_asgi),
])

if __name__ == "__main__":
    # Read the port from the environment variable, defaulting to 8000 if not set.
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="127.0.0.1", port=port)

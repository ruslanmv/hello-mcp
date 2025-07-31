# agents/hello_world/server_sse.py
import logging
from mcp.server import MCPServer
from mcp.server.transports.sse import SseTransport

# Set up basic logging to see server activity
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)

PORT = 8000

# 1. Create a standard MCP Server instance.
mcp = MCPServer()

@mcp.tool()
def hello(name: str) -> str:
    """Returns a simple greeting to the provided name."""
    logging.info(f"Tool 'hello' called with name: {name}")
    return f"Hello, {name}!"

if __name__ == "__main__":
    # 2. Create an instance of the SseTransport, specifying the host and port.
    #    The default endpoint path is /sse.
    transport = SseTransport(host="127.0.0.1", port=PORT)
    logging.info(f"Starting SSE server on http://127.0.0.1:{PORT}/sse")

    # 3. Pass the transport object to mcp.run() to start the HTTP server.
    mcp.run(transport)

# agents/hello_world/server_stdio.py

from mcp.server import MCPServer

# 1. Create a standard MCP Server instance.
mcp = MCPServer()

@mcp.tool()
def hello(name: str) -> str:
    """Returns a simple greeting to the provided name."""
    return f"Hello, {name}!"

if __name__ == "__main__":
    # 2. When run directly, mcp.run() without arguments defaults to
    #    using stdin/stdout for communication.
    mcp.run()
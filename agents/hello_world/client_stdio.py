#!/usr/bin/env python3
import asyncio
import sys
from pathlib import Path

from mcp import ClientSession
from mcp.client.stdio import stdio_client, StdioServerParameters
from mcp.types import TextContent


async def main():
    # Determine the path to the server script, relative to this client file
    script_dir = Path(__file__).resolve().parent
    server_script = script_dir / "server_stdio.py"
    if not server_script.exists():
        print(f"Error: server script not found at {server_script}")
        sys.exit(1)

    # Use the same Python executable that's running this client
    python_exe = sys.executable

    # Parameters for spawning the stdio server process
    server_params = StdioServerParameters(
        command=python_exe,
        args=[str(server_script)],
    )

    try:
        # Connect using the stdio transport
        async with stdio_client(server_params) as (read_stream, write_stream):
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

    except FileNotFoundError as e:
        print(f"Failed to start server process: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error during MCP session: {e}")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())

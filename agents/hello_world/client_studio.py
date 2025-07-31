# agents/hello_world/client_stdio.py

import asyncio
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

async def main():
    """
    This client demonstrates the STDIO transport method.
    It launches the server as a subprocess.
    """
    print("--- Running MCP client and server over STDIO ---")

    # 1. Define the command to launch the server script.
    server_params = StdioServerParameters(
        command="python",
        args=["agents/hello_world/server_stdio.py"],
    )

    # 2. stdio_client is a context manager that starts the server process
    #    and provides reader/writer streams to communicate with it.
    async with stdio_client(server_params) as (reader, writer):
        # 3. The ClientSession handles the MCP protocol over the streams.
        async with ClientSession(reader, writer) as session:
            # Initialize the MCP connection.
            await session.initialize()

            # 4. Call the 'hello' tool. The response is a dictionary.
            response = await session.call_tool("hello", {"name": "STDIO World"})
            
            # The actual return value is in the 'result' key.
            print(f"Server response: {response['result']}")

if __name__ == "__main__":
    asyncio.run(main())
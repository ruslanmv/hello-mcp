# MCP Core: Hello World Agent

This project demonstrates how to build a simple "Hello World" agent using the core `mcp` library, without the `fastmcp` wrapper. It is structured to highlight two different communication methods: **STDIO** and **SSE (HTTP)**.

The agent exposes a single tool, **`hello`**, which returns a greeting to a given name.

## 📂 File Structure

```
.
├── agents/
│   └── hello_world/
│       ├── client_sse.py       # Client for the SSE server
│       ├── client_stdio.py     # Client for the STDIO server
│       ├── server_sse.py       # The SSE (HTTP) agent server
│       └── server_stdio.py     # The STDIO agent server
├── Makefile
├── pyproject.toml
└── README.md
```

## ✅ Requirements

  * Python 3.11 or later
  * `make` command-line utility

## 🚀 Getting Started

### 1\. Installation

First, set up the Python virtual environment and install the required dependencies using the `Makefile`.

```
make install
```

-----

## Version 1: STDIO Communication

In this model, the client launches the server as a subprocess and they communicate over pipes (`stdin`/`stdout`). The server only exists for the duration of the client's session.

### Run the STDIO Demo

Execute the following command:

```
make run-stdio
```

This command runs the `client_stdio.py` script, which automatically starts `server_stdio.py`, calls the `hello` tool, prints the response, and then terminates.

**Expected Output:**

```
--- Running MCP client and server over STDIO ---
Server response: Hello, STDIO World!
```

-----

## Version 2: SSE (HTTP) Communication

In this model, the server is a standalone, persistent process that listens for network connections. Clients connect to it over HTTP. This allows a single server to handle multiple clients.

### Step 1: Start the SSE Server

First, start the server in the background:

```
make start-sse
```

This will launch the server, which will listen on `http://127.0.0.1:8000/sse`.

### Step 2: Run the SSE Client

With the server running, open another terminal (or use the same one) and run the client:

```
make run-client-sse
```

The client will connect to the running server, call the `hello` tool, and print the response.

**Expected Output:**

```
--- Connecting to SSE server at http://127.0.0.1:8000/sse ---
Server response: Hello, SSE World!
```

### Step 3: Stop the SSE Server

When you are finished, stop the background server process:

```
make stop-sse
```

-----

## Key Differences: STDIO vs. SSE

| Feature | STDIO (Standard I/O) | SSE (HTTP) |
| :--- | :--- | :--- |
| **Lifecycle** | The server's lifecycle is tied to the client. It starts and stops with the client. | The server is a persistent, long-running process, independent of any single client. |
| **Communication**| Uses standard input/output pipes. No network ports are involved. | Uses HTTP and Server-Sent Events over a network socket. |
| **Use Case** | Ideal for self-contained scripts or tools where an agent is needed temporarily. | Ideal for building robust services that need to be available to multiple clients or other services on a network. |
| **Complexity** | Simpler to run as a single command. The client manages the server process. | Requires separate steps to start/stop the server. More closely resembles a typical client-server architecture. |

## Makefile Commands

| Command | Description |
| :--- | :--- |
| `make install` | Installs all project dependencies. |
| `make run-stdio` | Runs the self-contained STDIO client/server demo. |
| `make start-sse` | Starts the SSE agent server in the background. |
| `make run-client-sse`| Runs the client to connect to the SSE server. |
| `make stop-sse` | Stops the background SSE agent server. |
| `make clean` | Stops the server and removes the virtual environment and build artifacts. |
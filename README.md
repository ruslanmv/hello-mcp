# MCP Core: Hello World Agent

This project demonstrates how to build a minimal “Hello World” agent using the core `mcp` library, **without** the `FastMCP` helper. It includes two interchangeable transport modes:

1. **STDIO** — the client spawns the server as a subprocess and they talk over pipes (`stdin`/`stdout`).
2. **SSE (HTTP)** — the server runs as a standalone HTTP service, and clients connect via Server-Sent Events.

---

## 📂 Repository Layout

```

.
├── agents/
│   └── hello\_world/
│       ├── server\_stdio.py     # STDIO‐based MCP server
│       ├── client\_stdio.py     # Client that launches & uses the STDIO server
│       ├── server\_sse.py       # SSE (HTTP)‐based MCP server
│       └── client\_sse.py       # Client for the SSE server
├── Makefile
├── pyproject.toml
└── README.md

````

---

## ✅ Prerequisites

- **Python 3.11 +**  
- **make** (GNU Make)

---

## 🚀 Quickstart

Install dependencies and set up your virtual environment:

```bash
make install
````

---

## Version 1: STDIO Communication

In STDIO mode, the client script **launches** the server subprocess and communicates over pipes. The server lives only as long as the client.

### Commands

* **Start & run demo (server + client)**

  ```bash
  make run-stdio
  ```

  This will:

  1. Kill any old STDIO server.
  2. Launch `agents/hello_world/server_stdio.py` in the background.
  3. Run `agents/hello_world/client_stdio.py` (which calls the `hello` tool).
  4. Print the greeting, then exit.

* **Manually start the STDIO server**

  ```bash
  make start-stdio
  ```

  Background‐launches the server alone and records its PID in `.stdio-pid`.

* **Run client against existing STDIO server**

  ```bash
  make run-client-stdio
  ```

* **Stop the STDIO server**

  ```bash
  make stop-stdio
  ```

### Expected Output

```plain
Initialized session: meta=None protocolVersion='2025-06-18' …
Available tools: ['hello']
Server says: Hello, stdio World!
```

---

## Version 2: SSE (HTTP) Communication

In SSE mode, the server is a standalone HTTP service at port 8000. Clients connect via Server-Sent Events, allowing multiple clients to share one server.

### Commands

* **Start the SSE server**

  ```bash
  make start-sse
  ```

  * Launches `agents/hello_world/server_sse.py` on `http://127.0.0.1:8000/messages/`
  * Waits until the port is listening, then saves its PID to `.sse-pid`.

* **Run the SSE client**

  ```bash
  make run-client-sse
  ```

  * Connects to `http://127.0.0.1:8000/messages/`
  * Lists tools and invokes `hello`.

* **Stop the SSE server**

  ```bash
  make stop-sse
  ```

### Expected Output

```plain
Initialized session: meta=None protocolVersion='2025-06-18' …
Available tools: ['hello']
Server says: Hello, SSE World!
```

---

## ⚖️ STDIO vs. SSE

| Aspect        | STDIO                                    | SSE (HTTP)                                     |
| :------------ | :--------------------------------------- | :--------------------------------------------- |
| **Server**    | Spawned by client; short‐lived           | Persistent background process                  |
| **Transport** | `stdin`/`stdout` pipes                   | HTTP + Server‐Sent Events                      |
| **Port**      | None                                     | TCP port 8000 (`/messages/` SSE endpoint)      |
| **Use case**  | One‐off tool integrations, local scripts | Multi‐client service, network‐accessible agent |

---

## 📖 Makefile Targets

| Target                  | Description                                                |
| :---------------------- | :--------------------------------------------------------- |
| `make install`          | Set up virtualenv & install dependencies.                  |
| **STDIO**               |                                                            |
| `make start-stdio`      | Launch STDIO server in background.                         |
| `make run-stdio`        | Start server (if needed) & run STDIO client.               |
| `make run-client-stdio` | Run STDIO client only.                                     |
| `make stop-stdio`       | Kill the background STDIO server.                          |
| **SSE (HTTP)**          |                                                            |
| `make start-sse`        | Launch SSE server on port 8000.                            |
| `make run-client-sse`   | Run client that connects to the SSE server.                |
| `make stop-sse`         | Kill the background SSE server.                            |
| **General**             |                                                            |
| `make clean`            | Stop any servers, remove the virtualenv & build artifacts. |

---

Happy building your MCP agents! Feel free to explore and extend these examples for your own tools and transports.

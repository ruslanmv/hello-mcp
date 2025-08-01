# Makefile for the MCP Core Project

.DEFAULT_GOAL := help

# --- Variables ---
PYTHON           := python3.11
VENV_NAME        := .venv
POETRY           := $(VENV_NAME)/bin/poetry
PID_FILE_SSE     := .sse-pid
PID_FILE_STDIO   := .stdio-pid
PORT             := 8000

# --- Phony Targets ---
.PHONY: all setup install run-stdio start-stdio run-client-stdio stop-stdio start-sse run-client-sse stop-sse clean help

help: ## Display this help message
	@echo "Usage: make <command>"
	@echo ""
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | sort \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Create the Python virtual environment
	@echo "--- Setting up virtual environment at $(VENV_NAME) ---"
	@if [ ! -d "$(VENV_NAME)" ]; then \
		$(PYTHON) -m venv $(VENV_NAME); \
		echo "--- Installing Poetry into the virtual environment ---"; \
		$(VENV_NAME)/bin/pip install --upgrade pip poetry; \
	else \
		echo "--- Virtual environment already exists. ---"; \
	fi
	@echo "--- Virtual environment is ready. ---"

install: setup ## Install all project dependencies
	@echo "--- Installing dependencies from pyproject.toml ---"
	$(POETRY) install
	@echo "--- Dependencies installed. ---"

# --- STDIO Server/Client ---

start-stdio: install ## Start the STDIO agent server in the background
	@echo "--- Ensuring no existing STDIO server is running... ---"
	@if [ -f $(PID_FILE_STDIO) ]; then \
		kill -9 $$(cat $(PID_FILE_STDIO)) 2>/dev/null || true; \
		rm -f $(PID_FILE_STDIO); \
	fi
	@echo "--- Starting STDIO server in background... ---"
	@$(POETRY) run python agents/hello_world/server_stdio.py & \
		echo $$! > $(PID_FILE_STDIO)
	@echo "--- ✅ STDIO Server started with PID $$(cat $(PID_FILE_STDIO)). ---"

run-stdio: start-stdio ## Run the STDIO client against the background server
	@$(POETRY) run python agents/hello_world/client_stdio.py

run-client-stdio: install ## Shortcut to run just the STDIO client (assumes server already running)
	@$(POETRY) run python agents/hello_world/client_stdio.py

stop-stdio: ## Stop the background STDIO agent server
	@echo "--- Stopping STDIO server ---"
	@if [ -f $(PID_FILE_STDIO) ]; then \
		echo "--- Killing PID $$(cat $(PID_FILE_STDIO))... ---"; \
		kill $$(cat $(PID_FILE_STDIO)) 2>/dev/null || true; \
		rm -f $(PID_FILE_STDIO); \
		echo "--- STDIO server stopped. ---"; \
	else \
		echo "--- No STDIO server PID file found. ---"; \
	fi

# --- SSE Server/Client ---

start-sse: install ## Start the SSE agent server in the background
	@echo "--- Ensuring port $(PORT) is free by stopping any existing server... ---"
	@-lsof -t -i:$(PORT) | xargs kill -9 > /dev/null 2>&1
	@rm -f $(PID_FILE_SSE)
	@echo "--- Starting SSE server in background... ---"
	@$(POETRY) run python agents/hello_world/server_sse.py &
	@echo "--- Waiting for server to become available on port $(PORT)... ---"
	@tries=0; \
	while ! lsof -i:$(PORT) -sTCP:LISTEN -t >/dev/null && [ $$tries -lt 20 ]; do \
		sleep 0.5; \
		tries=$$((tries + 1)); \
	done
	@if ! lsof -i:$(PORT) -sTCP:LISTEN -t >/dev/null; then \
		echo "--- ❌ Server failed to start. Check logs for errors. ---"; \
		exit 1; \
	fi
	@lsof -t -i:$(PORT) > $(PID_FILE_SSE)
	@echo "--- ✅ SSE Server started with PID $$(cat $(PID_FILE_SSE)) on port $(PORT). ---"

run-client-sse: install ## Run the client to connect to the SSE server
	@$(POETRY) run python agents/hello_world/client_sse.py

stop-sse: ## Stop the background SSE agent server
	@echo "--- Stopping SSE server ---"
	@if [ -f $(PID_FILE_SSE) ]; then \
		echo "--- Stopping process with PID $$(cat $(PID_FILE_SSE))... ---"; \
		kill $$(cat $(PID_FILE_SSE)) 2>/dev/null || true; \
		rm -f $(PID_FILE_SSE); \
		echo "--- Server stopped. ---"; \
	else \
		echo "--- PID file not found, no server to stop. ---"; \
	fi

clean: ## Stop all servers and remove the virtual environment and build artifacts
	@echo "--- Cleaning up project 🧹 ---"
	@$(MAKE) stop-stdio > /dev/null 2>&1
	@$(MAKE) stop-sse   > /dev/null 2>&1
	@rm -rf $(VENV_NAME)
	@rm -f $(PID_FILE_STDIO) $(PID_FILE_SSE) poetry.lock
	@find . -type f -name "*.pyc" -delete
	@find . -type d -name "__pycache__" -delete
	@echo "--- Cleanup complete. ---"

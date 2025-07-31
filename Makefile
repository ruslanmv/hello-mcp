# Makefile for the MCP Core Project

.DEFAULT_GOAL := help

# --- Variables ---
PYTHON      := python3.11
VENV_NAME   := .venv
POETRY      := $(VENV_NAME)/bin/poetry
PID_FILE    := .sse-pid
PORT        := 8000

# --- Phony Targets ---
.PHONY: all setup install run-stdio start-sse run-client-sse stop-sse clean help

# --- Main Targets ---

help: ## Display this help message
	@echo "Usage: make <command>"
	@echo ""
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

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
	@$(POETRY) install
	@echo "--- Dependencies installed. ---"

run-stdio: install ## Run the self-contained STDIO client/server demo
	@$(POETRY) run python agents/hello_world/client_stdio.py

start-sse: install ## Start the SSE agent server in the background
	@echo "--- Ensuring port $(PORT) is free by stopping any existing server... ---"
	@-lsof -t -i:$(PORT) | xargs kill -9 > /dev/null 2>&1
	@rm -f $(PID_FILE)
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
	@lsof -t -i:$(PORT) > $(PID_FILE)
	@echo "--- ✅ SSE Server started with PID $$(cat $(PID_FILE)) on port $(PORT). ---"

run-client-sse: install ## Run the client to connect to the SSE server
	@$(POETRY) run python agents/hello_world/client_sse.py

stop-sse: ## Stop the background SSE agent server
	@echo "--- Stopping SSE server ---"
	@if [ -f $(PID_FILE) ]; then \
		echo "--- Stopping process with PID $$(cat $(PID_FILE))... ---"; \
		kill $$(cat $(PID_FILE)) 2>/dev/null || true; \
		rm -f $(PID_FILE); \
		echo "--- Server stopped. ---"; \
	else \
		echo "--- PID file not found, no server to stop. ---"; \
	fi

clean: ## Stop the server and remove the virtual environment and build artifacts
	@echo "--- Cleaning up project 🧹 ---"
	@$(MAKE) stop-sse > /dev/null 2>&1
	@rm -rf $(VENV_NAME)
	@rm -f $(PID_FILE) poetry.lock
	@find . -type f -name "*.pyc" -delete
	@find . -type d -name "__pycache__" -delete
	@echo "--- Cleanup complete. ---"
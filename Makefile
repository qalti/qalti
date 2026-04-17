#!/usr/bin/env make

# Colors for better output
BOLD := \033[1m
RED := \033[31m
GREEN := \033[32m
YELLOW := \033[33m
BLUE := \033[34m
MAGENTA := \033[35m
CYAN := \033[36m
WHITE := \033[37m
NC := \033[0m# No Color

# Configuration
PYTHON := python3
VENV_DIR := .venv
VENV_BIN := $(VENV_DIR)/bin
VENV_PYTHON := $(VENV_BIN)/python
VENV_PIP := $(VENV_BIN)/pip
SCRIPT := scripts/build_qalti.py
XCODE_SCRIPT := scripts/xcode_build.sh

# Default target
.PHONY: help
help:
	@echo "$(BOLD)$(CYAN)🚀 Qalti Build Automation$(NC)"
	@echo ""
	@echo "$(BOLD)Main Targets:$(NC)"
	@echo "  $(GREEN)build$(NC)       	 - Full build with cleaning (format + lint + build)"
	@echo "  $(YELLOW)build-fast$(NC) 	 - Fast incremental build (no clean, no format)"
	@echo "  $(BLUE)xcode$(NC)          - Use Xcode environment (fixes tools issues)"
	@echo "  $(YELLOW)xcode-fast$(NC)     - Xcode build without cleaning"
	@echo "  $(MAGENTA)first-run$(NC)      - First-time setup with guidance"
	@echo ""
	@echo "$(BOLD)Development:$(NC)"
	@echo "  $(GREEN)format$(NC)         - Format Python code with black"
	@echo "  $(GREEN)lint$(NC)           - Lint Python code with flake8"
	@echo "  $(MAGENTA)reset-permissions$(NC) - Reset folder access permissions"
	@echo ""
	@echo "$(BOLD)Utilities:$(NC)"
	@echo "  $(WHITE)clean$(NC)          - Remove virtual environment"
	@echo "  $(WHITE)info$(NC)           - Show environment information"
	@echo ""
	@echo "$(BOLD)Testing:$(NC)"
	@echo "  $(CYAN)test$(NC)           - Run unit tests on macOS"
	@echo ""
	@echo "$(BOLD)$(GREEN)Quick start: make build$(NC)"

# Fast incremental build (most common use case)
.PHONY: build-fast
build-fast: $(VENV_DIR)
	@echo "$(BOLD)$(YELLOW)⚡ Fast Build (no clean, no format)...$(NC)"
	$(VENV_PYTHON) $(SCRIPT) --no-clean

# Full build with cleaning and code quality checks
.PHONY: build
build: venv format lint
	@echo ""
	@echo "$(BOLD)$(GREEN)🚀 Full Build Process...$(NC)"
	@echo "$(GREEN)📝 Code has been formatted and linted$(NC)"
	$(VENV_PYTHON) $(SCRIPT)

# Xcode environment build (fixes tool issues)
.PHONY: xcode
xcode:
	@echo ""
	@echo "$(BOLD)$(BLUE)🍎 Xcode Environment Build...$(NC)"
	@echo "$(BLUE)🔧 Using Xcode PATH to fix tool issues$(NC)"
	./$(XCODE_SCRIPT)

# Fast Xcode build without cleaning
.PHONY: xcode-fast
xcode-fast:
	@echo ""
	@echo "$(BOLD)$(BLUE)🍎 Fast Xcode Build (no clean)...$(NC)"
	./$(XCODE_SCRIPT) --no-clean

# Create virtual environment and install tools
.PHONY: venv
venv: $(VENV_DIR)

$(VENV_DIR):
	@echo "$(BOLD)$(CYAN)🔧 Creating Python virtual environment...$(NC)"
	$(PYTHON) -m venv $(VENV_DIR)
	@echo "$(CYAN)📦 Installing black and flake8...$(NC)"
	$(VENV_PIP) install --upgrade pip
	$(VENV_PIP) install black flake8
	@echo "$(BOLD)$(GREEN)✅ Virtual environment ready$(NC)"

# Format code with black
.PHONY: format
format: $(VENV_DIR)
	@echo "$(BOLD)$(GREEN)🎨 Formatting Python code...$(NC)"
	$(VENV_BIN)/black $(SCRIPT)
	@echo "$(GREEN)✅ Formatting complete$(NC)"

# Lint code with flake8
.PHONY: lint
lint: $(VENV_DIR)
	@echo "$(BOLD)$(GREEN)🔍 Linting Python code...$(NC)"
	$(VENV_BIN)/flake8 $(SCRIPT) --max-line-length=100 --extend-ignore=E203,W503
	@echo "$(GREEN)✅ Linting complete$(NC)"

# First-time setup with guidance
.PHONY: first-run
first-run: venv format lint
	@echo ""
	@echo "$(BOLD)$(MAGENTA)🎆 First Launch with Setup Guidance...$(NC)"
	@echo "$(MAGENTA)🚨 This includes detailed permission instructions$(NC)"
	$(VENV_PYTHON) $(SCRIPT) --first-launch

# Reset folder access permissions
.PHONY: reset-permissions
reset-permissions: $(VENV_DIR)
	@echo "$(BOLD)$(MAGENTA)🔓 Resetting folder access permissions...$(NC)"
	$(VENV_PYTHON) $(SCRIPT) --reset-permissions

# Clean up virtual environment
.PHONY: clean
clean:
	@echo "$(BOLD)$(WHITE)🧹 Cleaning virtual environment...$(NC)"
	rm -rf $(VENV_DIR)
	@echo "$(GREEN)✅ Cleanup complete$(NC)"

# Show environment information
.PHONY: info
info:
	@echo "$(BOLD)$(CYAN)📋 Environment Information:$(NC)"
	@echo "  $(CYAN)Python:$(NC) $(shell which $(PYTHON))"
	@echo "  $(CYAN)Python version:$(NC) $(shell $(PYTHON) --version)"
	@echo "  $(CYAN)Virtual env:$(NC) $(VENV_DIR)"
	@if [ -d "$(VENV_DIR)" ]; then \
		echo "  $(CYAN)Virtual env status:$(NC) $(GREEN)✅ Created$(NC)"; \
	else \
		echo "  $(CYAN)Virtual env status:$(NC) $(RED)❌ Not created$(NC) $(WHITE)(run 'make venv')$(NC)"; \
	fi
	@echo "  $(CYAN)Working directory:$(NC) $(PWD)"
	@echo "  $(CYAN)Build script:$(NC) $(SCRIPT)"
	@echo "  $(CYAN)Xcode script:$(NC) $(XCODE_SCRIPT)"

# Run unit tests on macOS
.PHONY: test
test:
	@echo "$(BOLD)$(CYAN)🧪 Running unit tests...$(NC)"
	xcodebuild test -project xcodeproject/Qalti.xcodeproj -scheme Qalti -destination 'platform=macOS,arch=arm64'

#
# Additional targets (less commonly used)
#

# Run the script directly without any setup
.PHONY: run-only
run-only: $(VENV_DIR)
	@echo "$(WHITE)🏃 Running script directly...$(NC)"
	$(VENV_PYTHON) $(SCRIPT)

# Force rebuild (clean then build)
.PHONY: rebuild
rebuild: clean build

# Check repository structure
.PHONY: check-repo
check-repo:
	@if [ ! -d "xcodeproject" ]; then \
		echo "$(BOLD)$(RED)❌ Error: xcodeproject directory not found$(NC)"; \
		echo "$(WHITE)Make sure you're in the repo root directory$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✅ Repository structure looks good$(NC)"

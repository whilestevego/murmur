PREFIX ?= $(HOME)/.local
BIN = .build/release

.PHONY: build test install uninstall

build: ## Release build of murmur and murmurd
	swift build -c release

test:
	swift test

install: build ## Install both commands into $(PREFIX)/bin (murmur finds murmurd beside it)
	install -d $(PREFIX)/bin
	install -m 755 $(BIN)/murmur $(BIN)/murmurd $(PREFIX)/bin/
	@echo "Installed to $(PREFIX)/bin. Next: murmur setup [--from <KokoroBundle>]"

uninstall:
	-murmur stop
	rm -f $(PREFIX)/bin/murmur $(PREFIX)/bin/murmurd

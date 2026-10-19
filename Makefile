PREFIX ?= $(HOME)/.local
BIN = .build/release

.PHONY: build test nemo install uninstall

build: ## Release build of murmur and murmurd
	swift build -c release

test:
	swift test

nemo: build ## Score the text cleanup against NeMo's English normalization cases (SHOW=1 lists failures)
	python3 Tests/nemo/score.py

install: build ## Install both commands into $(PREFIX)/bin (murmur finds murmurd beside it)
	install -d $(PREFIX)/bin
	install -m 755 $(BIN)/murmur $(BIN)/murmurd $(PREFIX)/bin/
	@echo "Installed to $(PREFIX)/bin. Next: murmur setup [--from <KokoroBundle>]"

uninstall:
	-murmur stop
	rm -f $(PREFIX)/bin/murmur $(PREFIX)/bin/murmurd

PREFIX ?= $(HOME)/.local
BIN = .build/release

.PHONY: build test nemo format lint install uninstall

build: ## Builds murmur and murmurd for release.
	swift build -c release

test:
	swift test

nemo: build ## Scores text normalization against NeMo's English test cases. Set SHOW=1 to list the failures.
	python3 Tests/nemo/score.py

format: ## Formats the Swift sources in place with swift-format.
	swift format format -i -r -p Sources Tests Package.swift

lint: ## Fails if formatting would change anything, or if code breaks a lint rule.
	swift format lint --strict -r -p Sources Tests Package.swift

# A running murmurd would keep running the old code, so install stops it first.
install: build ## Installs murmur and murmurd in $(PREFIX)/bin. murmur finds murmurd in the same directory.
	-pkill -x murmurd
	install -d $(PREFIX)/bin
	install -m 755 $(BIN)/murmur $(BIN)/murmurd $(PREFIX)/bin/
	@echo "Installed to $(PREFIX)/bin. Next: murmur setup [--from <KokoroBundle>]"

uninstall:
	-murmur stop
	rm -f $(PREFIX)/bin/murmur $(PREFIX)/bin/murmurd

MODE ?= DEBUG

ifeq ($(MODE),DEBUG)
    WEBPACK_MODE=development
    RUST_MODE=debug
else
    WEBPACK_MODE=production
    RUST_MODE=release
endif

RUST_BINARY = target/$(RUST_MODE)/mccraft_web_server

RUST_SOURCES = $(shell find -name '*.rs')
WEB_SOURCES = $(shell find ./mccraft_frontend/src) $(glob ./mccraft_frontend/%.json)

web: mccraft_frontend/dist/main.js $(RUST_BINARY)

serve: web
	$(RUST_BINARY) --serve-static mccraft_frontend/dist

mccraft_frontend/dist/main.js: $(WEB_SOURCES)
	cd mccraft_frontend && ./node_modules/.bin/webpack --mode $(WEBPACK_MODE)

target/debug/mccraft_web_server: $(RUST_SOURCES)
	cargo build -p mccraft_web_server

target/release/mccraft_web_server: $(RUST_SOURCES)
	cargo build --release -p mccraft_web_server

.PHONY: web serve

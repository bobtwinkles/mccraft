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


ifneq ($(IMAGE_PATH),)
  RUST_IMAGE_PATH=--image-path $(IMAGE_PATH)
else
  RUST_IMAGE_PATH=
endif

serve: web
	$(RUST_BINARY) --static-path mccraft_frontend/dist $(RUST_IMAGE_PATH)

mccraft_frontend/dist/main.js: $(WEB_SOURCES)
	cd mccraft_frontend && ./node_modules/.bin/webpack --mode $(WEBPACK_MODE)

target/debug/mccraft_web_server: $(RUST_SOURCES)
	cargo build -p mccraft_web_server

target/release/mccraft_web_server: $(RUST_SOURCES)
	cargo build --release -p mccraft_web_server

.PHONY: web serve

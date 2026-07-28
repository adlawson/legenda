APP_NAME := Legenda
BUNDLE   := $(APP_NAME).app
CONFIG   := release
BIN      := .build/$(CONFIG)/$(APP_NAME)

.PHONY: all build debug test app run install kill clean release cask

all: app

build:
	swift build -c $(CONFIG)

debug:
	swift build

test:
	swift test

app: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	codesign --force --sign - $(BUNDLE)
	@echo "Built $(BUNDLE)"

run: kill app
	open $(BUNDLE)

install: app
	rm -rf /Applications/$(BUNDLE)
	cp -R $(BUNDLE) /Applications/
	@echo "Installed /Applications/$(BUNDLE)"

kill:
	@pkill -x $(APP_NAME) 2>/dev/null || true

# Normally done by the release workflow on a v* tag; these are for building the
# same artifacts locally. Usage: make release VERSION=0.1.0
release:
	@test -n "$(VERSION)" || (echo "usage: make release VERSION=0.1.0" >&2; exit 1)
	./script/build-release.sh $(VERSION)

cask:
	@test -n "$(VERSION)" || (echo "usage: make cask VERSION=0.1.0" >&2; exit 1)
	./script/build-brew-cask.sh --version $(VERSION) \
		--zip .release/$(APP_NAME)-v$(VERSION).zip

clean:
	rm -rf .build $(BUNDLE)

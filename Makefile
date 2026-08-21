.PHONY: app run debug test clean icon dmg gift snapshot

# Command Line Tools-only machines (no Xcode) ship Testing.framework outside
# the default search paths; full Xcode and CI need no flags.
DEV_DIR := $(shell xcode-select -p)/Library/Developer
TEST_FLAGS := $(shell [ -d "$(DEV_DIR)/Frameworks/Testing.framework" ] && echo "-Xswiftc -F$(DEV_DIR)/Frameworks -Xlinker -F$(DEV_DIR)/Frameworks -Xlinker -rpath -Xlinker $(DEV_DIR)/Frameworks -Xlinker -rpath -Xlinker $(DEV_DIR)/usr/lib")

app:
	./scripts/make-app.sh release

debug:
	./scripts/make-app.sh debug

run: app
	open dist/Dangle.app

test:
	swift test $(TEST_FLAGS)

# Renders the default pack; set DANGLE_PACK=path/to/pack.json to render another.
snapshot:
	swift run -c release DangleSnapshot "$${DANGLE_PACK:-Packs/default/pack.json}" snapshots/

icon:
	./scripts/make-icon.sh

dmg: app
	./scripts/make-dmg.sh

# Build a personalized app + DMG from any pack:
#   make gift PACK=Packs/local/yourpack/pack.json
gift:
ifndef PACK
	$(error make gift needs PACK=path/to/pack.json)
endif
	DANGLE_BUNDLE_PACK="$(PACK)" ./scripts/make-app.sh release
	./scripts/make-dmg.sh

clean:
	rm -rf .build dist snapshots

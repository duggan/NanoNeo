# NanoNeo — build, bundle, sign, and notarize a Developer-ID macOS menu bar app
# that saves AlphaSmart Neo drafts over USB. Needs only the Swift toolchain that
# ships with Xcode (plus an Apple ID for `make release`). GPL-3.0.

APP_NAME := NanoNeo
APP_ID   := ie.duggan.NanoNeo
TEAM_ID  := PSPQTHW392

# Override if your identity string differs:
#   make sign SIGN_ID="Developer ID Application: Your Name (TEAMID)"
SIGN_ID ?= Developer ID Application: Ross Duggan (PSPQTHW392)

BUILD_CONFIG ?= release
ARCHFLAGS    ?= --arch arm64 --arch x86_64
APP_BUNDLE   := build/$(APP_NAME).app
CONTENTS     := $(APP_BUNDLE)/Contents
DMG          := build/$(APP_NAME).dmg
ZIP          := build/$(APP_NAME)-notarize.zip

# Artwork. Each is optional: the build still works while any of them is missing.
APP_ICON       := Resources/$(APP_NAME).icns
MENU_BAR_ICONS := $(wildcard Resources/MenuBarIcon*Template*.png)
DMG_BACKGROUND := Resources/dmg-background.tiff

# `xcrun notarytool store-credentials` keychain profile (see `make notary-setup`).
NOTARY_PROFILE ?= nanoneo

# Styled "drag to Applications" DMG layout (built with create-dmg). The
# background is left out until Resources/dmg-background.png exists.
DMG_STAGE := build/dmg-src
DMG_OPTS  := --volname "$(APP_NAME)" \
             $(if $(wildcard $(DMG_BACKGROUND)),--background "$(DMG_BACKGROUND)") \
             --window-pos 200 120 --window-size 660 420 --icon-size 120 \
             --icon "$(APP_NAME).app" 175 215 --hide-extension "$(APP_NAME).app" \
             --app-drop-link 485 215 --no-internet-enable

.PHONY: all build bundle sign run test icons demo dmg release notary-setup clean help

all: sign ## Build, bundle, and sign (default)

build: ## Compile the universal (arm64+x86_64) binaries with SwiftPM
	swift build -c $(BUILD_CONFIG) $(ARCHFLAGS)

bundle: build ## Assemble the .app bundle from the built binary
	@set -e; \
	BIN="$$(swift build -c $(BUILD_CONFIG) $(ARCHFLAGS) --show-bin-path)"; \
	echo "Using bin path: $$BIN"; \
	rm -rf "$(APP_BUNDLE)"; \
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"; \
	cp "$$BIN/$(APP_NAME)App" "$(CONTENTS)/MacOS/$(APP_NAME)"; \
	cp Resources/App-Info.plist "$(CONTENTS)/Info.plist"; \
	if [ -f "$(APP_ICON)" ]; then cp "$(APP_ICON)" "$(CONTENTS)/Resources/"; \
	else echo "note: $(APP_ICON) not found; bundling without an app icon"; fi; \
	for f in $(MENU_BAR_ICONS); do cp "$$f" "$(CONTENTS)/Resources/"; done; \
	echo "Assembled $(APP_BUNDLE)"

sign: bundle ## Code-sign with Hardened Runtime and verify
	codesign --force --options runtime --timestamp \
	  --sign "$(SIGN_ID)" --entitlements Resources/App.entitlements \
	  --identifier "$(APP_ID)" "$(APP_BUNDLE)"
	codesign --verify --strict --verbose=2 "$(APP_BUNDLE)"
	@echo "Signed & verified $(APP_BUNDLE)"

run: sign ## Sign then launch the app
	open "$(APP_BUNDLE)"

test: ## Run the NeoKit unit tests (no Neo needed)
	swift test

icons: ## Regenerate artwork from Resources/art/make_icons.py (needs Inkscape)
	@set -e; command -v inkscape >/dev/null || { echo "Inkscape is required: brew install --cask inkscape" >&2; exit 1; }; \
	ART=Resources/art; TMP="$$(mktemp -d)"; \
	python3 "$$ART/make_icons.py" >/dev/null; \
	mkdir -p "$$TMP/$(APP_NAME).iconset"; \
	for size in 16 32 128 256 512; do \
	  inkscape "$$ART/AppIcon.svg" -o "$$TMP/$(APP_NAME).iconset/icon_$${size}x$${size}.png" -w $$size -h $$size 2>/dev/null; \
	  inkscape "$$ART/AppIcon.svg" -o "$$TMP/$(APP_NAME).iconset/icon_$${size}x$${size}@2x.png" -w $$((size*2)) -h $$((size*2)) 2>/dev/null; \
	done; \
	iconutil -c icns "$$TMP/$(APP_NAME).iconset" -o "$(APP_ICON)"; \
	for name in MenuBarIcon MenuBarIconSyncing; do \
	  inkscape "$$ART/$$name.svg" -o "Resources/$${name}Template.png" -w 22 -h 18 2>/dev/null; \
	  inkscape "$$ART/$$name.svg" -o "Resources/$${name}Template@2x.png" -w 44 -h 36 2>/dev/null; \
	done; \
	inkscape "$$ART/DMGBackground.svg" -o "$$TMP/bg.png" -w 660 -h 420 2>/dev/null; \
	inkscape "$$ART/DMGBackground.svg" -o "$$TMP/bg@2x.png" -w 1320 -h 840 2>/dev/null; \
	sips -s dpiWidth 72 -s dpiHeight 72 "$$TMP/bg.png" >/dev/null; \
	sips -s dpiWidth 144 -s dpiHeight 144 "$$TMP/bg@2x.png" >/dev/null; \
	tiffutil -cathidpicheck "$$TMP/bg.png" "$$TMP/bg@2x.png" -out "$(DMG_BACKGROUND)" 2>/dev/null; \
	rm -rf "$$TMP"; \
	echo "Wrote $(APP_ICON), Resources/MenuBarIcon*Template*.png and $(DMG_BACKGROUND)"

demo: ## Render the README demo, docs/demo.gif (needs Node, Chrome, ffmpeg)
	@set -e; command -v ffmpeg >/dev/null || { echo "ffmpeg is required: brew install ffmpeg" >&2; exit 1; }; \
	TMP="$$(mktemp -d)"; \
	python3 Resources/art/make_icons.py >/dev/null; \
	npm install --silent --prefix "$$TMP" playwright@1.48.2 >/dev/null; \
	NODE_PATH="$$TMP/node_modules" node Resources/art/demo/render.js "$$TMP/frames"; \
	ffmpeg -v error -y -framerate 20 -i "$$TMP/frames/%04d.png" \
	  -vf "scale=1280:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" \
	  -loop 0 docs/demo.gif; \
	rm -rf "$$TMP"; \
	echo "Wrote docs/demo.gif"

dmg: sign ## Build a signed (not-yet-notarized) styled DMG for local testing
	@command -v create-dmg >/dev/null || { echo "create-dmg not found: brew install create-dmg" >&2; exit 1; }
	rm -f "$(DMG)"
	rm -rf "$(DMG_STAGE)" && mkdir -p "$(DMG_STAGE)"
	ditto "$(APP_BUNDLE)" "$(DMG_STAGE)/$(APP_NAME).app"
	create-dmg $(DMG_OPTS) "$(DMG)" "$(DMG_STAGE)" || true
	@test -f "$(DMG)" || { echo "create-dmg did not produce $(DMG)" >&2; exit 1; }
	codesign --force --timestamp --sign "$(SIGN_ID)" "$(DMG)"
	@echo "Built styled $(DMG) (signed only; run 'make release' to notarize)"

release: sign ## Full notarized release: staple the .app, then build+notarize the DMG
	@command -v create-dmg >/dev/null || { echo "create-dmg not found: brew install create-dmg" >&2; exit 1; }
	# 1. Notarize + staple the app, so it's valid offline once copied out of the DMG.
	ditto -c -k --keepParent "$(APP_BUNDLE)" "$(ZIP)"
	xcrun notarytool submit "$(ZIP)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(APP_BUNDLE)"
	rm -f "$(ZIP)"
	# 2. Build the styled DMG from the stapled app, then notarize + staple it.
	rm -f "$(DMG)"
	rm -rf "$(DMG_STAGE)" && mkdir -p "$(DMG_STAGE)"
	ditto "$(APP_BUNDLE)" "$(DMG_STAGE)/$(APP_NAME).app"
	create-dmg $(DMG_OPTS) "$(DMG)" "$(DMG_STAGE)" || true
	@test -f "$(DMG)" || { echo "create-dmg did not produce $(DMG)" >&2; exit 1; }
	codesign --force --timestamp --sign "$(SIGN_ID)" "$(DMG)"
	xcrun notarytool submit "$(DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(DMG)"
	xcrun stapler validate "$(DMG)"
	@echo "Release ready (notarized + stapled): $(DMG)"

notary-setup: ## One-time: store an Apple ID app-specific password for notarytool
	@echo "Create an app-specific password at https://appleid.apple.com, then run once:"
	@echo ""
	@echo "  xcrun notarytool store-credentials $(NOTARY_PROFILE) \\"
	@echo "      --apple-id <your-apple-id> --team-id $(TEAM_ID) --password <app-specific-password>"
	@echo ""
	@echo "Afterwards, 'make release' notarizes without prompting."

clean: ## Remove build artifacts
	rm -rf .build build

help: ## List targets
	@grep -E '^[a-z][a-z-]*:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-13s %s\n", $$1, $$2}'

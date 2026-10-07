APP       := DMC
BUNDLE    := build/$(APP).app
BIN       := .build/arm64-apple-macosx/release/$(APP)
CONFIG    := release
DMG       := build/$(APP).dmg

# Stamped into the bundle's Info.plist. The release workflow passes the tag (VERSION=0.2.0);
# a local build keeps whatever Resources/Info.plist says.
VERSION      ?= $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)

.PHONY: all build bundle run install dmg clean

all: bundle

build:
	swift build -c $(CONFIG) --arch arm64

bundle: build
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	@cp "$(BIN)" "$(BUNDLE)/Contents/MacOS/$(APP)"
	@cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $(VERSION)" \
		-c "Set CFBundleVersion $(BUILD_NUMBER)" "$(BUNDLE)/Contents/Info.plist"
	@cp Resources/AppIcon.icns "$(BUNDLE)/Contents/Resources/AppIcon.icns"
	@cp Resources/tta_data.json "$(BUNDLE)/Contents/Resources/tta_data.json"
	@cp Resources/scene-templates.json "$(BUNDLE)/Contents/Resources/scene-templates.json"
	@cp Resources/effect-templates.json "$(BUNDLE)/Contents/Resources/effect-templates.json"
	@printf 'APPL????' > "$(BUNDLE)/Contents/PkgInfo"
	@codesign --force --sign - "$(BUNDLE)" 2>/dev/null
	@echo "built $(BUNDLE) ($(VERSION))"

run: bundle
	@pkill -x $(APP) 2>/dev/null || true
	@open "$(BUNDLE)"

install: bundle
	@rm -rf "/Applications/$(APP).app"
	@cp -R "$(BUNDLE)" /Applications/
	@echo "installed /Applications/$(APP).app"

# Ad-hoc signed, not notarized: there is no Developer ID behind this project, so the site walks
# people through Privacy & Security → Open Anyway. The checksum goes up beside the image.
dmg: bundle
	@rm -rf build/dmg "$(DMG)" "$(DMG).sha256"
	@mkdir -p build/dmg
	@ditto "$(BUNDLE)" "build/dmg/$(APP).app"
	@ln -s /Applications build/dmg/Applications
	@hdiutil create -volname "$(APP) $(VERSION)" -srcfolder build/dmg -ov -format UDZO "$(DMG)" >/dev/null
	@rm -rf build/dmg
	@cd build && shasum -a 256 "$(APP).dmg" > "$(APP).dmg.sha256"
	@echo "built $(DMG) ($(VERSION))"

clean:
	@rm -rf .build build

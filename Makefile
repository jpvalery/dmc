APP       := DMC
BUNDLE    := build/$(APP).app
BIN       := .build/arm64-apple-macosx/release/$(APP)
CONFIG    := release

.PHONY: all build bundle run install clean

all: bundle

build:
	swift build -c $(CONFIG) --arch arm64

bundle: build
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	@cp "$(BIN)" "$(BUNDLE)/Contents/MacOS/$(APP)"
	@cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	@cp Resources/AppIcon.icns "$(BUNDLE)/Contents/Resources/AppIcon.icns"
	@cp Resources/tta_data.json "$(BUNDLE)/Contents/Resources/tta_data.json"
	@printf 'APPL????' > "$(BUNDLE)/Contents/PkgInfo"
	@codesign --force --sign - "$(BUNDLE)" 2>/dev/null
	@echo "built $(BUNDLE)"

run: bundle
	@pkill -x $(APP) 2>/dev/null || true
	@open "$(BUNDLE)"

install: bundle
	@rm -rf "/Applications/$(APP).app"
	@cp -R "$(BUNDLE)" /Applications/
	@echo "installed /Applications/$(APP).app"

clean:
	@rm -rf .build build

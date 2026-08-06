.PHONY: build run clean xcode resolve format lint icons run-xcode test help

SWIFT := swift
CONFIG ?= debug
BUILD_DIR := .build/arm64-apple-macosx/$(CONFIG)
APP_BUNDLE := DSBrain.app
APP_PATH := $(APP_BUNDLE)/Contents/MacOS/DSBrain
HELPER_PATH := $(APP_BUNDLE)/Contents/MacOS/smc-helper
PLIST_PATH := $(APP_BUNDLE)/Contents/Info.plist
ICONS_DIR := $(APP_BUNDLE)/Contents/Resources

build:
	$(SWIFT) build -c release --product DSBrain
	$(SWIFT) build -c release --product smc-helper

build-release: build

build-debug:
	$(SWIFT) build --product DSBrain
	$(SWIFT) build --product smc-helper

test:
	$(SWIFT) test --filter DSBrainTests

bundle: build-$(CONFIG)
	@echo "Creating .app bundle..."
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(ICONS_DIR)
	@cp "$(BUILD_DIR)/DSBrain" $(APP_PATH)
	@chmod +x $(APP_PATH)
	@cp "$(BUILD_DIR)/smc-helper" $(HELPER_PATH)
	@chmod +x $(HELPER_PATH)
	@cp DSBrain/Info.plist $(APP_BUNDLE)/Contents/
	@cp -R DSBrain/Assets.xcassets $(ICONS_DIR)/
	@cp DSBrain/AppIcon.icns $(ICONS_DIR)/AppIcon.icns
	@echo "Bundle ready: $(APP_BUNDLE)"

bundle-debug: CONFIG = debug
bundle-debug: bundle

bundle-release: CONFIG = release
bundle-release: bundle

run: bundle-debug
	@echo ""
	@echo "Launching DSBrain..."
	@open $(APP_BUNDLE)

run-release: bundle-release
	@echo ""
	@echo "Launching DSBrain (release)..."
	@open $(APP_BUNDLE)

clean:
	$(SWIFT) package clean
	@rm -rf $(APP_BUNDLE)

resolve:
	$(SWIFT) package resolve

xcode:
	open Package.swift

format:
	@command -v swiftformat >/dev/null 2>&1 || { echo "Install swiftformat first: brew install swiftformat"; exit 1; }
	swiftformat DSBrain/

lint:
	@command -v swiftlint >/dev/null 2>&1 || { echo "Install swiftlint first: brew install swiftlint"; exit 1; }
	swiftlint DSBrain/

icons:
	@echo "Generating status bar icons..."
	sips -z 40 40 icon.png --out DSBrain/Assets.xcassets/StatusBarIcon.imageset/statusbar@2x.png >/dev/null
	sips -z 20 20 icon.png --out DSBrain/Assets.xcassets/StatusBarIcon.imageset/statusbar.png >/dev/null
	@echo "Generating app icons..."
	sips -z 16 16 icon.png --out DSBrain/Assets.xcassets/AppIcon.appiconset/app-16.png >/dev/null
	sips -z 32 32 icon.png --out DSBrain/Assets.xcassets/AppIcon.appiconset/app-32.png >/dev/null
	sips -z 128 128 icon.png --out DSBrain/Assets.xcassets/AppIcon.appiconset/app-128.png >/dev/null
	sips -z 256 256 icon.png --out DSBrain/Assets.xcassets/AppIcon.appiconset/app-256.png >/dev/null
	sips -z 512 512 icon.png --out DSBrain/Assets.xcassets/AppIcon.appiconset/app-512.png >/dev/null
	sips -z 1024 1024 icon.png --out DSBrain/Assets.xcassets/AppIcon.appiconset/app-1024.png >/dev/null
	@echo "Generating AppIcon.icns..."
	@rm -rf /tmp/DSBrain-AppIcon.iconset
	@mkdir -p /tmp/DSBrain-AppIcon.iconset
	@sips -z 16 16 icon.png --out /tmp/DSBrain-AppIcon.iconset/icon_16x16.png >/dev/null
	@sips -z 32 32 icon.png --out /tmp/DSBrain-AppIcon.iconset/icon_16x16@2x.png >/dev/null
	@sips -z 32 32 icon.png --out /tmp/DSBrain-AppIcon.iconset/icon_32x32.png >/dev/null
	@sips -z 64 64 icon.png --out /tmp/DSBrain-AppIcon.iconset/icon_32x32@2x.png >/dev/null
	@sips -z 128 128 icon.png --out /tmp/DSBrain-AppIcon.iconset/icon_128x128.png >/dev/null
	@sips -z 256 256 icon.png --out /tmp/DSBrain-AppIcon.iconset/icon_128x128@2x.png >/dev/null
	@sips -z 256 256 icon.png --out /tmp/DSBrain-AppIcon.iconset/icon_256x256.png >/dev/null
	@sips -z 512 512 icon.png --out /tmp/DSBrain-AppIcon.iconset/icon_256x256@2x.png >/dev/null
	@sips -z 512 512 icon.png --out /tmp/DSBrain-AppIcon.iconset/icon_512x512.png >/dev/null
	@sips -z 1024 1024 icon.png --out /tmp/DSBrain-AppIcon.iconset/icon_512x512@2x.png >/dev/null
	@iconutil -c icns /tmp/DSBrain-AppIcon.iconset -o DSBrain/AppIcon.icns
	@echo "Icons generated."

run-xcode:
	$(XCODEBUILD) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath .build/xcode build

help:
	@echo "DSBrain — macOS menu bar app for ds4-server"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@awk '/^# / { \
		desc = substr($$0, 3); \
		next \
	} \
	/^[a-zA-Z_-]+:/ { \
		gsub(/:.*$$/, "", $$1); \
		printf "  %-16s %s\n", $$1, desc \
	}' Makefile

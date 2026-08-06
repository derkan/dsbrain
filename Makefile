.PHONY: build build-debug build-release bundle bundle-debug bundle-release run run-release release clean xcode resolve format lint icons run-xcode test help

SWIFT := swift
CONFIG ?= debug
BUILD_DIR = .build/arm64-apple-macosx/$(CONFIG)
APP_BUNDLE := DSBrain.app
APP_PATH := $(APP_BUNDLE)/Contents/MacOS/DSBrain
HELPER_PATH := $(APP_BUNDLE)/Contents/MacOS/smc-helper
PLIST_PATH := $(APP_BUNDLE)/Contents/Info.plist
ICONS_DIR := $(APP_BUNDLE)/Contents/Resources
VERSION ?= $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' DSBrain/Info.plist)
RELEASE_ZIP = DSBrain-$(VERSION)-macos-arm64.zip

build:
	$(SWIFT) build -c release --product DSBrain
	$(SWIFT) build -c release --product smc-helper

build-release: build

build-debug:
	$(SWIFT) build --product DSBrain
	$(SWIFT) build --product smc-helper

test:
	$(SWIFT) test --filter DSBrainTests

# $(1) = debug | release — explicit so we never ship a debug binary as "release".
define BUNDLE_CMD
	@echo "Creating .app bundle ($(1))..."
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(ICONS_DIR)
	@cp ".build/arm64-apple-macosx/$(1)/DSBrain" $(APP_PATH)
	@chmod +x $(APP_PATH)
	@cp ".build/arm64-apple-macosx/$(1)/smc-helper" $(HELPER_PATH)
	@chmod +x $(HELPER_PATH)
	@cp DSBrain/Info.plist $(APP_BUNDLE)/Contents/
	@cp -R DSBrain/Assets.xcassets $(ICONS_DIR)/
	@cp DSBrain/AppIcon.icns $(ICONS_DIR)/AppIcon.icns
	@echo "Bundle ready: $(APP_BUNDLE)"
endef

bundle-debug: build-debug
	$(call BUNDLE_CMD,debug)

bundle-release: build-release
	$(call BUNDLE_CMD,release)

# Default `make bundle` follows CONFIG (debug unless overridden).
bundle:
	@$(MAKE) --no-print-directory bundle-$(CONFIG)

run: bundle-debug
	@echo ""
	@echo "Launching DSBrain..."
	@open $(APP_BUNDLE)

run-release: bundle-release
	@echo ""
	@echo "Launching DSBrain (release)..."
	@open $(APP_BUNDLE)

# Release zip: DSBrain-<version>-macos-arm64.zip (VERSION from Info.plist or override)
release: bundle-release
	@test -n "$(VERSION)" || { echo "VERSION is empty"; exit 1; }
	@rm -f "$(RELEASE_ZIP)"
	ditto -c -k --keepParent "$(APP_BUNDLE)" "$(RELEASE_ZIP)"
	@echo "Release artifact: $(RELEASE_ZIP)"

clean:
	$(SWIFT) package clean
	@rm -rf $(APP_BUNDLE)
	@rm -f DSBrain-*-macos-arm64.zip

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

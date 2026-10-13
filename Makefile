APP := quick-prompt
BUILD_DIR := build
APP_PATH := $(BUILD_DIR)/Build/Products/Release/$(APP).app
INSTALL_DIR := $(HOME)/Applications
SUBSYSTEM := com.hectormiko.quick-prompt

.PHONY: generate build test install run logs clean

generate:
	xcodegen generate --quiet

build: generate
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Release \
		-derivedDataPath $(BUILD_DIR) -allowProvisioningUpdates -quiet build

test:
	swift test --package-path Packages/QuickPromptCore

install: build
	-pkill -x $(APP)
	rm -rf "$(INSTALL_DIR)/$(APP).app"
	mkdir -p "$(INSTALL_DIR)"
	cp -R "$(APP_PATH)" "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/$(APP).app"

run: install

logs:
	log stream --level debug --predicate 'subsystem == "$(SUBSYSTEM)"'

clean:
	rm -rf $(BUILD_DIR) $(APP).xcodeproj

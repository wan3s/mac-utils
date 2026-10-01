APP_NAME   := MacUtils
PROJECT    := $(APP_NAME).xcodeproj
CONFIG     ?= Release
BUILD_DIR  := build
APP_PATH   := $(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP_NAME).app

.PHONY: all project build run install clean

all: build

project:
	xcodegen generate --quiet

build: project
	xcodebuild -project $(PROJECT) -scheme $(APP_NAME) -configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR) -destination 'platform=macOS' -quiet build

run: build
	-pkill -x $(APP_NAME)
	open $(APP_PATH)

install: build
	-pkill -x $(APP_NAME)
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP_PATH) /Applications/
	open /Applications/$(APP_NAME).app

clean:
	rm -rf $(BUILD_DIR) $(PROJECT)

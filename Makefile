XCODE     := DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
PROJECT   := PremiereProTimelineQuickLook.xcodeproj
SCHEME    := PremiereProTimelineQuickLook
BUILD_DIR := /tmp/PremiereQLBuild

.PHONY: generate build install open reset-ql clean

generate:
	xcodegen generate

## Open in Xcode — easiest way to build with your Apple ID (automatic signing)
open: generate
	open $(PROJECT)

## Build from command line (requires TEAM=<your-team-id>)
## Example: make build TEAM=AB12CD34EF
build: generate
	$(XCODE) xcodebuild \
		-project $(PROJECT) \
		-scheme  $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		$(if $(TEAM),DEVELOPMENT_TEAM=$(TEAM),) \
		build

install: build
	cp -Rf "$(BUILD_DIR)/Build/Products/Debug/PremiereProTimelineQuickLook.app" \
	       "/Applications/PremiereProTimelineQuickLook.app"
	qlmanage -r && qlmanage -r cache

reset-ql:
	qlmanage -r && qlmanage -r cache && killall Finder || true

clean:
	rm -rf /tmp/PremiereQLBuild

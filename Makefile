APP := CodexTouchBar.app
BINARY := .build/CodexTouchBar
LABEL := com.piyadanai.codex-touch-bar
INSTALLED_APP := $(HOME)/Applications/$(APP)
INSTALLED_BINARY := $(INSTALLED_APP)/Contents/MacOS/CodexTouchBar
LAUNCH_AGENT := $(HOME)/Library/LaunchAgents/$(LABEL).plist
DOMAIN := gui/$(shell id -u)

.PHONY: build app test status install uninstall clean

build:
	mkdir -p .build
	xcrun swiftc -O -framework AppKit -framework CoreLocation Sources/CodexTouchBar/main.swift -o $(BINARY)

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BINARY) $(APP)/Contents/MacOS/CodexTouchBar
	cp Assets/farm-*.png $(APP)/Contents/Resources/
	cp Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

test: build
	$(BINARY) --self-test

status: build
	$(BINARY) --status

install: app test
	launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null || true
	mkdir -p $(HOME)/Applications $(HOME)/Library/LaunchAgents
	rm -rf $(INSTALLED_APP)
	cp -R $(APP) $(INSTALLED_APP)
	plutil -create xml1 $(LAUNCH_AGENT)
	plutil -insert Label -string $(LABEL) $(LAUNCH_AGENT)
	plutil -insert ProgramArguments -json '["$(INSTALLED_BINARY)"]' $(LAUNCH_AGENT)
	plutil -insert RunAtLoad -bool true $(LAUNCH_AGENT)
	plutil -insert KeepAlive -bool true $(LAUNCH_AGENT)
	launchctl bootstrap $(DOMAIN) $(LAUNCH_AGENT)
	launchctl kickstart -k $(DOMAIN)/$(LABEL)

uninstall:
	launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null || true
	rm -rf $(INSTALLED_APP)
	rm -f $(LAUNCH_AGENT)

clean:
	rm -rf .build $(APP)

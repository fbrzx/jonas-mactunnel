.PHONY: build install

build:
	bash apps/menubar/build.sh

install: build
	@pkill -f "Jonas Tunnel" 2>/dev/null || true
	@sleep 1
	@rm -rf ~/Applications/"Jonas Tunnel.app"
	@cp -r apps/menubar/"Jonas Tunnel.app" ~/Applications/"Jonas Tunnel.app"
	@open ~/Applications/"Jonas Tunnel.app"
	@echo "Jonas Tunnel installed and launched."

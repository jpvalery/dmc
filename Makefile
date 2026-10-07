# The macOS app lives in app/ and the website in site/. App targets forward to app/Makefile,
# so `make run` and `make dmg` work from the repository root.

.PHONY: all build bundle run install dmg clean site site-dev

all build bundle run install dmg clean:
	@$(MAKE) -C app $@

site:
	cd site && npm run build

site-dev:
	cd site && npm run dev

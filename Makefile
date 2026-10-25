# Currents — Dev workflow (works from Linux via GitHub Actions)
#
# Since we can't run Xcode on Linux, this Makefile provides shortcuts
# for triggering CI builds, checking status, and common dev tasks.

.PHONY: help ci ci-status ci-logs lint test-local clean screenshots-frame appstore-check appstore-setup appstore-status appstore-metadata appstore-screenshots appstore-events appstore-pages appstore-gamecenter appstore-media appstore-art appstore-images push-test

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

ci: ## Trigger a CI build (push current branch)
	git push origin $$(git branch --show-current)
	@echo ""
	@echo "CI triggered. Run 'make ci-status' to check progress."

ci-status: ## Check latest CI run status
	gh run list --limit 5

ci-logs: ## Stream logs from the latest CI run
	gh run watch $$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')

ci-download: ## Download build artifacts from latest CI run
	rm -rf build-logs Currents-simulator Currents-IPA
	gh run download $$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')

ci-ipa: ## Download just the IPA from latest CI run
	rm -rf Currents-IPA
	gh run download $$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId') -n Currents-IPA
	@echo ""
	@echo "IPA downloaded to Currents-IPA/Currents.ipa"
	@echo "Install with: AltStore, TrollStore, or SideStore"

screenshots-frame: ## Frame raw captures in ios/screenshots/6.9 with headlines, then render in-app event media
	uv run scripts/frame_screenshots.py --input ios/screenshots/6.9 --output ios/screenshots/6.9-framed --captions ios/AppStore/captions.json
	uv run scripts/render_event_media.py --input ios/screenshots/6.9 --events ios/AppStore/events --output ios/screenshots/events

appstore-check: ## Check App Store Connect text against Apple's limits
	uv run scripts/check_appstore_metadata.py ios/AppStore/metadata

# App Store Connect publishing. ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH come
# from the environment or .env.local. Nothing here submits for review.
ASC_ENV = scripts/with_asc_env.sh
BUNDLER ?= $(or $(shell command -v bundle 2>/dev/null),$(firstword $(wildcard $(HOME)/.local/share/gem/ruby/*/bin/bundle)),bundle)
BUNDLE = cd ios && $(CURDIR)/$(ASC_ENV) env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 FASTLANE_SKIP_UPDATE_CHECK=1 $(BUNDLER) exec fastlane
APPLY_FLAG = $(if $(filter 1 yes true,$(APPLY)),--apply,)

appstore-setup: ## Install fastlane into ios/vendor/bundle
	cd ios && $(BUNDLER) install

appstore-status: ## Latest builds with processing and TestFlight state
	$(ASC_ENV) uv run scripts/asc.py status

appstore-metadata: appstore-check ## Upload listing text for en-US, en-GB and es-MX (fastlane deliver)
	$(BUNDLE) ios metadata

appstore-screenshots: ## Replace listing screenshots with the app-store-screenshots branch, or STORE_ART_DIR (fastlane deliver)
	$(if $(STORE_ART_DIR),export STORE_ART_DIR=$(abspath $(STORE_ART_DIR)) &&,) $(BUNDLE) ios screenshots

appstore-events: ## In-app events; dry run unless APPLY=1, START=YYYY-MM-DD sets the dates
	$(ASC_ENV) uv run scripts/asc.py events $(if $(START),--start $(START),) $(APPLY_FLAG)

appstore-pages: ## Custom product pages; dry run unless APPLY=1
	$(ASC_ENV) uv run scripts/asc.py pages $(APPLY_FLAG)

appstore-gamecenter: ## Game Center achievements, leaderboards and challenges; dry run unless APPLY=1
	$(ASC_ENV) uv run scripts/asc.py gamecenter $(APPLY_FLAG)

appstore-media: ## App preview, header and search results art from ios/build/appstore-media; dry run unless APPLY=1
	$(ASC_ENV) uv run scripts/asc.py media $(APPLY_FLAG)

# The whole set of store images, rendered into STORE_ART and then swapped in
# without touching any text: listing screenshots, preview, header, search
# results, in-app event images and the custom product pages' screenshots.
STORE_ART = ios/build/appstore-media

appstore-art: ## Render screenshots, event images, header video and (with FOOTAGE=dir) the preview from STILLS=dir
	@test -n "$(STILLS)" || { echo "usage: make appstore-art STILLS=<captures folder> [FOOTAGE=<clips folder>]"; exit 2; }
	uv run scripts/store_art.py --shots $(STILLS) --out $(STORE_ART)
	uv run scripts/render_banner.py
	$(if $(FOOTAGE),cd ios/AppStore/preview && bun install --frozen-lockfile && bun render.ts --stills $(abspath $(STILLS)) --footage $(abspath $(FOOTAGE)) --out $(abspath $(STORE_ART))/preview.mp4,)

appstore-images: ## Replace every App Store image from STORE_ART, text untouched; dry run unless APPLY=1
	$(ASC_ENV) uv run scripts/asc.py events --images-only --art $(STORE_ART) $(APPLY_FLAG)
	$(ASC_ENV) uv run scripts/asc.py pages --images-only --art $(STORE_ART) $(APPLY_FLAG)
	$(ASC_ENV) uv run scripts/asc.py media $(APPLY_FLAG)
	$(if $(APPLY_FLAG),$(MAKE) appstore-screenshots STORE_ART_DIR=$(STORE_ART)/6.9,@echo "Listing screenshots: APPLY=1 replaces them with $(STORE_ART)/6.9")

# CloudKit pushes to one device. CK_KEY_ID and CK_KEY_PATH (server-to-server
# key) come from the environment or .env.local.
push-test: ## Send every CloudKit push to CODE's phone; dry run unless APPLY=1
	@test -n "$(CODE)" || { echo "usage: make push-test CODE=<friend code> [APPLY=1]"; exit 2; }
	scripts/with_ck_env.sh uv run scripts/push_test.py --code $(CODE) $(APPLY_FLAG)

swift-check: ## Check Swift syntax (requires swift on PATH)
	@which swift > /dev/null 2>&1 && \
		cd ios && swift package resolve && swift build 2>&1 || \
		echo "Swift not installed locally — use 'make ci' to build via GitHub Actions"

lint: ## Run basic checks on Swift files
	@echo "Checking for common issues..."
	@grep -rn "TODO\|FIXME\|HACK" ios/Currents/ --include="*.swift" || echo "No TODOs found"
	@echo ""
	@echo "File count by directory:"
	@find ios/Currents -name "*.swift" | sed 's|/[^/]*$$||' | sort | uniq -c | sort -rn

tree: ## Show project structure
	@find ios/Currents -name "*.swift" | sort | sed 's|ios/||'

clean: ## Clean build artifacts
	rm -rf ios/.build ios/.swiftpm ios/.spm-cache
	rm -rf ios/Currents.xcodeproj

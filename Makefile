# Currents — Dev workflow (works from Linux via GitHub Actions)
#
# Since we can't run Xcode on Linux, this Makefile provides shortcuts
# for triggering CI builds, checking status, and common dev tasks.

.PHONY: help ci ci-status ci-logs lint test-local clean

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

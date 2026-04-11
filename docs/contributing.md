# Contributing

Thanks for your interest in Currents.

## Development loop

```bash
cd ios
xcodegen generate
open Currents.xcodeproj
```

Or `make ios` from the repo root.

The app has no backend, so there is nothing to run alongside Xcode. Launch the simulator and go.

## Testing

Unit tests live in `ios/Tests/`. Run them from Xcode (`⌘U`) or the command line:

```bash
cd ios
xcodebuild test \
  -project Currents.xcodeproj \
  -scheme CurrentsTests \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro"
```

The forecast engine is the primary test target because it's a pure function of its inputs — new factors should land with a test exercising at least the edge conditions (very high / very low pressure, storm conditions, outside the species temperature optimum).

## Style

- Swift 5.10 / iOS 26
- Two spaces for indentation (`.swiftformat` enforces this)
- No third-party UI frameworks — SwiftUI only
- Actors for anything async with mutable state, pure structs for anything deterministic
- Prefer `async/await` over Combine

## Commit messages

Short imperative subject, body when the reason isn't obvious:

```
Add tide phase weighting to forecast engine

Storm fronts shifted the optimum inland by ~3 hours during November
testing; weighting the phase transition separately from the level
gives a visibly better match to the logged-catch validation set.
```

## Pull requests

Keep PRs focused — a PR that touches the forecast engine and the map view is two PRs. Reviewers will ask you to split.

CI runs on every PR: simulator build, device `.ipa` build, unit tests. A red PR won't merge.

## License

By contributing you agree your changes will be released under the same MIT license as the rest of the project.

# LANreader Agent Guide

Use this file as the source of truth for Codex-style work in this repository.

## Start Here

- Prefer the repo scripts over retyping `xcodebuild` or CI commands:
  - `./scripts/bootstrap`
  - `./scripts/lint`
  - `./scripts/test-ios`
- The scripts use the normal Xcode folders by default.
- Set `LANREADER_USE_LOCAL_XCODE_ENV=1` if you explicitly want repo-local caches under `.codex/`.
- The current project, app, and scheme names are `LANreader`.

## Project Facts

- Xcode project: `LANreader.xcodeproj`
- Main app scheme: `LANreader`
- Secondary scheme: `Action`
- Test target: `LANreaderTests`
- CI simulator destination: `platform=iOS Simulator,OS=26.2,name=iPad Pro 11-inch (M5)`
- CI lint command: `swiftlint --strict`
- CI test command: `xcodebuild clean test -project LANreader.xcodeproj -scheme LANreader ... -skipMacroValidation`
- Current active GitHub workflows are `ci.yml` and `manual-ipa-release.yml`.
- Local unsigned IPA packaging is supported.

## Repo Map

- `LANreader/LANreaderApp.swift`: app entry point, logging bootstrap, app-wide tasks.
- `LANreader/Page/`: reader, paging, image display, archive details.
- `LANreader/Library/`, `LANreader/Category/`, `LANreader/Search/`, `LANreader/Setting/`: feature UIs.
- `LANreader/Service/`: LANraragi API client, translation, image handling, transaction observer.
- `LANreader/Database/`: GRDB database setup and records.
- `Action/`: action extension target.
- `LANreaderTests/`: XCTest coverage, mostly service tests with HTTP stubs.
- `ci_scripts/`: CI bootstrap helpers, including Swift macro trust config.

## Architecture Notes

- The app is a mixed SwiftUI/UIKit project, not a pure SwiftUI app.
- SwiftUI is used for feature composition and state-driven views, but performance-sensitive scrolling surfaces use UIKit wrappers.
- `UIArchiveList.swift`, `UIPageCollection.swift`, `UICacheView.swift`, and related cells/controllers use `UIViewControllerRepresentable`, `UIHostingController`, and `UICollectionView` to avoid the poor performance previously seen with pure SwiftUI `LazyHStack` and `LazyVStack` approaches.
- Treat the UIKit collection view layer as an intentional performance decision, not legacy code to rewrite away by default.
- The app is SwiftUI-based at the feature level and uses the Composable Architecture heavily across feature views.
- Dependencies are injected through `Dependencies` where the code already follows that pattern.
- Persistence uses `GRDB` and `GRDBQuery`.
- Networking and streaming logic live under `LANreader/Service/`.
- Reader rendering has special handling for animated images and HEIC conversion; inspect `ImageService.swift`, `UIPageCell.swift`, and `PageImageV2.swift` together before changing image behavior.

## Testing Conventions

- Service tests use `XCTest` with `OHHTTPStubs` and `OHHTTPStubsSwift`.
- Existing tests configure LANraragi URL and API key through `UserDefaults` in `setUp()`.
- Tests clear `UserDefaults` and remove HTTP stubs in teardown.
- When changing LANraragi API behavior, add or update stubbed tests before relying on simulator-only verification.
- There is limited coverage outside service logic. For reader or image changes, prefer adding focused unit tests where feasible.

## Working Rules

- Keep changes aligned with existing TCA and dependency-injection patterns. Do not rewrite features into a different architecture as a drive-by cleanup.
- Do not replace UIKit-backed collection views with pure SwiftUI `LazyVStack`, `LazyHStack`, or similar containers unless the task explicitly asks for that change and performance has been re-validated.
- When changing reader, archive grid, or cache-list behavior, inspect the SwiftUI wrapper and the UIKit controller/cell together before deciding where the fix belongs.
- Prefer narrow fixes. This repo has some legacy naming and release automation debt; do not normalize unrelated names unless the task is explicitly about release tooling or rebranding.
- If you need a local build, use the scripts in `scripts/`. They use the normal Xcode folders by default and support repo-local cache overrides when needed.
- Before commit, push, or PR creation, run `./scripts/lint` and verify it passes. Treat lint as a required pre-PR gate.
- If you touch CI or release automation, treat `.github/workflows/ci.yml` and `.github/workflows/manual-ipa-release.yml` as the active sources of truth.

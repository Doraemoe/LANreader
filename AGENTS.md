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

- Default branch: `master`
- Xcode project: `LANreader.xcodeproj`
- Main app scheme: `LANreader`
- Secondary scheme: `Action`
- Test target: `LANreaderTests`
- CI selects Xcode 26.6 from `/Applications/Xcode_26.6.app`.
- CI simulator destination: `platform=iOS Simulator,OS=26.5,name=iPad Pro 11-inch (M5)`
- CI lint command: `swiftlint --strict`
- CI test command: `xcodebuild clean test -project LANreader.xcodeproj -scheme LANreader ... -skipMacroValidation`
- Current active GitHub workflows are `ci.yml` and `manual-ipa-release.yml`.
- Local unsigned IPA packaging is supported.
- Manual releases derive tags as `<MARKETING_VERSION>-<CURRENT_PROJECT_VERSION>`.

## Repo Map

- `LANreader/LANreaderApp.swift`: app entry point, logging bootstrap, app-wide tasks.
- `LANreader/Page/`: reader, paging, image display, archive details.
- `LANreader/Models/`: LANraragi response models and app-facing view models.
- `LANreader/Library/`, `LANreader/Category/`, `LANreader/Search/`, `LANreader/Setting/`: feature UIs.
- `LANreader/Service/`: LANraragi API client, translation, image handling, transaction observer.
- `LANreader/Database/`: GRDB database setup and records.
- `Action/`: action extension target.
- `LANreaderTests/`: XCTest coverage for services, reducers, reader positioning, and extracted feature logic.
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
- Reader navigation crosses three ownership layers: `ArchiveReader.swift` owns feature state and intent, `ReaderPositioning.swift` owns pure index calculations, and `UIPageCollection.swift` performs UIKit scrolling. Inspect all three before changing page jumps, restore behavior, double-page layout, or RTL behavior.

## Reader and Cache Invariants

- LANraragi page numbers are one-based. Reader collection indices are zero-based and can diverge further when split-page items are inserted. Resolve server-facing page numbers through `PageFeature.State.pageNumber` or `sourcePageNumber` instead of treating them as collection indices.
- Preserve `ReaderNavigationSource` when requesting a jump. Initial restore and slider jumps are centered, while chapter, tap, keyboard, and automatic navigation are edge-aligned.
- Chapter metadata follows the full path from the LANraragi response to `ArchiveItem.toc`, then to `ArchiveCache.toc` for offline reading. Keep the property optional so older servers and existing cache rows remain valid.
- Opening a cached archive must remain offline. Do not add a network request to recover missing chapter metadata or other optional metadata; if it was not persisted when the archive was cached, leave the related UI unavailable.
- Persisted cache-model changes require an additive GRDB migration in `AppDatabase.swift` and backward-compatible decoding. Do not rewrite or rename an existing migration after it may have shipped.
- Tankoubon chapter navigation flattens the real TOCs from its contained archives. Offset each one-based local chapter page by the actual number of extracted pages from preceding archives, and ignore entries outside their source archive's extracted page range. Add the included archive title as a default chapter at its first page unless a valid manual chapter already starts there.

## Tankoubon Boundaries

- Treat IDs with the `TANK_` prefix as Tankoubons via `isTankoubonArchiveId`. Thumbnail, metadata, progress, update, and delete operations must use the `/api/tankoubons/...` endpoints instead of archive endpoints.
- Tankoubon reading flattens contained archives into one global reader sequence while retaining each page's source archive ID and source page number. Keep global progress/navigation separate from per-archive page downloads and image lookup.
- Tankoubon details have editable Tankoubon-level tags and read-only tags inherited from included archives. Updating local metadata must not write inherited tags back to the Tankoubon.

## LANraragi API Conventions

- Keep request and response shapes aligned with the upstream LANraragi OpenAPI specification at `https://github.com/Difegue/LANraragi/blob/dev/tools/openapi.yaml`.
- Do not rely on Alamofire's default parameter encoding when the specification defines query parameters. Use explicit query-string encoding, including for `POST` and `PUT` requests.
- Service tests should verify the complete request contract that matters: HTTP method, path, query parameters, authorization header, and body encoding.

## Testing Conventions

- Service tests use `XCTest` with `OHHTTPStubs` and `OHHTTPStubsSwift`.
- Existing tests configure LANraragi URL and API key through `UserDefaults` in `setUp()`.
- Tests clear `UserDefaults` and remove HTTP stubs in teardown.
- When changing LANraragi API behavior, add or update stubbed tests before relying on simulator-only verification.
- Reader reducer and positioning behavior belongs in focused `ArchiveReaderFeatureTests` coverage, including relevant single-page, double-page, split-page, RTL, cached, and Tankoubon cases.
- For behavior, persistence, service, or reader changes, run `./scripts/lint` and `./scripts/test-ios` before creating a PR. Documentation-only changes do not require an Xcode test run.

## Pull Request Versioning

When asked to create a pull request:

- Always increment `CURRENT_PROJECT_VERSION` by exactly 1, even when the user does not explicitly request a build-number bump. Keep all LANreader and Action target build settings in sync.
- Before creating the PR, read the current `MARKETING_VERSION`, tell the user its value, and ask whether it should be bumped. If the user already specified the marketing-version change, do not ask again.
- If a marketing-version bump is requested, update all LANreader and Action target build settings together.
- Verify the resolved values across every build configuration in `LANreader.xcodeproj/project.pbxproj`; do not update only the main app target or only one configuration.

## Working Rules

- Keep changes aligned with existing TCA and dependency-injection patterns. Do not rewrite features into a different architecture as a drive-by cleanup.
- Do not replace UIKit-backed collection views with pure SwiftUI `LazyVStack`, `LazyHStack`, or similar containers unless the task explicitly asks for that change and performance has been re-validated.
- When changing reader, archive grid, or cache-list behavior, inspect the SwiftUI wrapper and the UIKit controller/cell together before deciding where the fix belongs.
- Prefer narrow fixes. This repo has some legacy naming and release automation debt; do not normalize unrelated names unless the task is explicitly about release tooling or rebranding.
- Add user-facing strings to `Localizable.xcstrings`; do not hard-code new English UI copy in Swift views.
- If you need a local build, use the scripts in `scripts/`. They use the normal Xcode folders by default and support repo-local cache overrides when needed.
- Before committing, review `git diff` and `git status` so unrelated or pre-existing worktree changes are not included.
- If you touch CI or release automation, treat `.github/workflows/ci.yml` and `.github/workflows/manual-ipa-release.yml` as the active sources of truth.

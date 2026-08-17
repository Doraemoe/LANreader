# AI-native quality

LANreader optimizes for fast iteration without asking reviewers to trust the amount of code produced or an agent's confidence. Quality comes from executable constraints, evidence matched to risk, and a feedback loop that turns escaped defects into durable protection.

## Verification loop

1. Make the smallest coherent change and add focused tests at the real behavior boundary.
2. Run `./scripts/verify-changes [base-ref]` while iterating.
3. Run `./scripts/verify` before handing off product or build changes.
4. Record exact commands, outcomes, and behavior evidence in the pull request.
5. Let CI rerun the full command independently on pull requests and `master`.
6. If a defect escapes, add a regression test and improve the narrowest durable guardrail.

`verify-changes` is an iteration accelerator, not a weaker merge gate. It chooses among:

| Tier | Typical changes | Checks |
| --- | --- | --- |
| Fast | Documentation, contribution templates, localization catalogs | Whitespace plus JSON, string catalog, property list, Xcode project, YAML, and shell syntax validation |
| Lint | SwiftLint configuration | Fast checks plus strict SwiftLint |
| Full | App, extension, tests, Xcode project, dependency, build/quality scripts, CI workflows, macro trust, or unknown files | Fast checks, strict SwiftLint, and the iOS test suite |

CI always runs the full tier. It cancels stale runs, also verifies the merged `master` state, and preserves failed Xcode result bundles for diagnosis.

## Match evidence to risk

| Risk surface | Required evidence |
| --- | --- |
| Reader/navigation | Focused reducer and positioning tests for the relevant single/double, split-page, right-to-left, cached, and Tankoubon cases; exercise the affected UIKit boundary where applicable |
| Image pipeline | Tests or a repeatable manual scenario covering the relevant animated-image, HEIC, sizing, reuse, and cancellation behavior |
| LANraragi API | Stubbed service tests proving method, path, query parameters, authorization header, and body encoding |
| Persistence/offline | Additive migration coverage, backward-compatible decoding, and proof that cached archives stay offline |
| Localized UI | Valid string catalogs, established terminology, and compilation of the consuming target |
| Project/CI/release | Repository structural checks plus the exact build, test, packaging, or workflow path affected |

Passing tests are necessary but not automatically sufficient. A helper-only test can miss broken integration, and high line coverage can still miss boundary cases. Prefer a small number of tests that constrain the actual user path and important invariants.

## Durable knowledge

Use three layers, in this order:

1. Encode mechanically checkable rules in scripts, lint, tests, or CI.
2. Put stable repository invariants and ownership guidance in `AGENTS.md`.
3. Capture decisions that explain a long-lived tradeoff in `docs/decisions/`.

Do not create a decision record for routine implementation detail. Use one when future contributors might reasonably undo the choice without understanding its constraints. Start from [the decision template](../decisions/TEMPLATE.md).

For a user-impacting or systemic escaped defect, start from [the postmortem template](../postmortems/TEMPLATE.md). A postmortem is complete only when it identifies why existing gates missed the issue and links the regression test or guardrail that now detects it.

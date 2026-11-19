**English** · [简体中文](CONTRIBUTING.zh-Hans.md)

# Contributing

Causality is a SwiftUI app for macOS plus a separate model-layer Swift Package. Changes usually go in the order model layer → command line → interface, and the model-layer tests are the only hard gate.

## Setup

- macOS 15+, Xcode 16+
- `xcodegen` (`brew install xcodegen`)
- No developer certificate needed: Debug builds are ad-hoc signed by default

## Running the checks

```bash
./scripts/check.sh            # swift test + CLI self-check + xcodegen + build + app tests
cd Packages/CausalityCore && swift test
cd Packages/CausalityCore && swift run causal bench
```

After editing `project.yml` or adding files under `Sources/Causality/**`, run `xcodegen generate` before building. `check.sh` does that for you.

## How to write code

- Write comments in Chinese, saying why rather than what; keep names in line with the code around them.
- The model layer stays on Foundation + Observation, with no SwiftUI.
- Every project change goes through `EditOperation`, so a single undo reverses it; don't mutate the arrays directly.
- New schema fields are optional and default when decoding, so older packages still open; write the current `schemaVersion` to disk.
- A new rule gets a model-layer test first, then a CLI assertion in `scripts/check.sh`, then the interface.
- Ordering that crosses `await` — saving, switching projects — belongs in `Tests/CausalityAppTests`: control the timing with the `SaveQueue.setBeforeSave` write gate, not with sleep.
- Keep API keys, certificates and personal paths out of the repository; `Config/Local.xcconfig` is already ignored.

## Commits

One commit does one thing, and the message says what changed and why. Run the tests and the CLI self-check before you commit.

## Credentials and network

- AI keys come from environment variables (`CAUSAL_*_KEY`), the Release keychain, or a 0600 `credentials.plist` in Debug.
- The model-layer tests do not touch the network.
- Turn off the system proxy before notarising, or `codesign` can get a 502 when it fetches a timestamp; `scripts/release.sh` checks for this ahead of time.

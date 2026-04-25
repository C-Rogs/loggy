# Loggy

Single-user, local-first **Hevy-style workout logger** for iPhone (SwiftUI + SQLite via GRDB).

## Docs and rules

- Project instructions: [`AGENTS.md`](AGENTS.md)
- Product, flows, schema, import mapping: [`Docs/`](Docs/)
- Cursor rules: [`.cursor/rules/`](.cursor/rules/)

## Build (Xcode)

This repo uses **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** so the Xcode project stays reproducible.

1. Install XcodeGen (e.g. `brew install xcodegen`).
2. From the repo root:

```bash
xcodegen generate
open Loggy.xcodeproj
```

3. Select the **Loggy** scheme, pick a simulator or device, **Run**.

The first run generates `Loggy.xcodeproj` from [`project.yml`](project.yml). Do not hand-edit the pbxproj; change `project.yml` or Swift sources under [`App/`](App/) instead.

### Command-line build

If `xcodebuild` reports no eligible simulator destinations, install a simulator runtime (Xcode **Settings → Components**, or `xcodebuild -downloadPlatform iOS`), then:

```bash
xcodebuild -scheme Loggy -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

## Swift source layout

See [`App/`](App/) — Domain, Persistence (GRDB), Services, ViewModels, UI, Widgets (Live Activity extension).

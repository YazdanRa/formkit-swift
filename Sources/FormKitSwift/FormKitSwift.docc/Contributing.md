# Contributing

Keep changes small, schema-driven, and verified against the package's public behavior.

## Prerequisites

Use macOS with Xcode and Swift 6, plus Git. The demo additionally needs XcodeGen. Local hooks use Prek, SwiftLint, and SwiftFormat.

## Set Up the Package

```bash
git clone https://github.com/YazdanRa/formkit-swift.git
cd formkit-swift
swift package resolve
prek install
```

Use a path dependency while developing against another local package or app:

```swift
.package(path: "../formkit-swift")
```

## Verify a Change

Build and test with warnings treated as errors:

```bash
swift build -c release -Xswiftc -warnings-as-errors
swift test -Xswiftc -warnings-as-errors
```

Run the repository's formatting and lint checks:

```bash
swiftlint --quiet --force-exclude
swiftformat . --lint --swift-version 6.3
prek run --all-files
```

Build DocC with warnings treated as errors:

```bash
scripts/make-docs.sh .build/docc-site formkit-swift
```

## Run the Demo

```bash
cd Example/FormKitSwiftDemo
xcodegen generate
xcodebuild build \
  -project FormKitSwiftDemo.xcodeproj \
  -scheme FormKitSwiftDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

## Contribution Principles

- Put shared form behavior in the renderer or session instead of duplicating it in controls.
- Preserve the distinction between missing, `null`, blank, and concrete JSON values.
- Keep networking, persistence, telemetry, and host models outside the package.
- Reuse package descriptors and component contexts at public customization boundaries.
- Add the smallest regression test that fails before a nontrivial fix and passes after it.
- Keep unrelated formatting or generated changes out of the diff.

Use conventional commits such as `feat(renderer): support a schema keyword`, `fix(session): preserve nullable values`, or `docs(docc): document uploads`.

For the complete repository workflow, see `CONTRIBUTING.md` at the repository root.

# Contributing

This repository contains a standalone Swift package at the repository root and an example app under `Example/FormKitSwiftDemo`.

## Prerequisites

- macOS with Xcode and the Swift 6 toolchain
- Git
- XcodeGen when building the demo app
- Prek, SwiftLint, and SwiftFormat when running hooks locally

## Setup

Clone the repository and enter the package root:

```bash
git clone <repo-url>
cd formkit-swift
```

During local development from another SwiftPM or Xcode project, use a path dependency:

```swift
.package(path: "../formkit-swift")
```

Resolve dependencies:

```bash
swift package resolve
```

## Development Workflow

Start by checking the current tree:

```bash
git status --short
```

Build the package in release mode:

```bash
swift build -c release -Xswiftc -warnings-as-errors
```

Run the full test suite:

```bash
swift test -Xswiftc -warnings-as-errors
```

Run formatting and lint checks:

```bash
swiftlint --quiet --force-exclude
swiftformat . --lint --swift-version 6.3
```

Build DocC documentation:

```bash
scripts/make-docs.sh .build/docc-site formkit-swift
```

## Demo App

The demo app lives in `Example/FormKitSwiftDemo`.

```bash
cd Example/FormKitSwiftDemo
xcodegen generate
xcodebuild build -project FormKitSwiftDemo.xcodeproj -scheme FormKitSwiftDemo -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

## Commit Messages

Use conventional commit messages:

```text
feat(renderer): support conditional object sections
fix(session): preserve hidden draft values
docs(readme): clarify tool edit usage
test(renderer): cover array validation errors
```

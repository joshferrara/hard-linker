<img src="Icon-iOS-Default-1024x1024@1x.png" width="200px" />

# Hard Linker

Hard Linker is a native macOS utility for creating hard-linked copies of selected files and folders with `cp -al`.

## Features

- Drag and drop files or folders, or choose them with the native file picker
- Link multiple sources into one destination folder
- Preflight validation for duplicate target names, existing targets, missing files, and recursive destination choices
- Native progress and status feedback
- Sparkle-based automatic update support

## What are hard links?

Hard links are directory entries that point to the same file data on disk. They are useful for space-efficient copies because additional hard links do not duplicate file contents.

On macOS, directories themselves are not hard-linked. When you choose a folder, Hard Linker creates the destination directory structure and hard-links the files inside it through `cp -al`.

Hard links must be created on the same volume. Cross-volume attempts will fail.

## Requirements

- macOS 13.0 or later
- Read access to selected sources and write access to the selected destination

## Installation

1. Download the latest `Hard-Linker.zip` from the GitHub releases page.
2. Unzip it and move `Hard-Linker.app` to `/Applications`.
3. Right-click and choose Open the first time if macOS Gatekeeper prompts.

## Usage

1. Add one or more source files or folders.
2. Choose a destination folder.
3. Click Create Hard Links.

Each selected source is linked into the destination using its original file or folder name. If that target path already exists, the app stops before running `cp`.

## Development

Build and run the Swift package:

```bash
swift build
swift run HardLinkCreator
```

Run tests:

```bash
swift test
```

Create a signed release bundle:

```bash
./build-and-release.sh -v 1.0.7 -b 7
```

The release script expects a Developer ID signing identity, notarization profile, and Sparkle private key to be available locally or in CI.

## Project Structure

```text
Hardlinker/
├── .github/workflows/release.yml
├── AppIcon.icns
├── AppIcon.iconset/
├── Package.swift
├── README.md
├── Sources/
│   └── HardLinkCreator/
│       ├── Entitlements.plist
│       └── HardLinkCreator.swift
├── Tests/
│   └── HardLinkCreatorTests/
│       └── HardLinkPlanTests.swift
├── appcast.xml
└── build-and-release.sh
```

## License

Copyright © 2025 Josh Ferrara. All rights reserved.

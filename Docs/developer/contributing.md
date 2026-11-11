# Working on SKTiled

How to build, test and change the library itself.

- [Repository Layout](#repository-layout)
- [Toolchain](#toolchain)
- [Everyday Commands](#everyday-commands)
- [Tests](#tests)
- [Documentation](#documentation)
- [Code Conventions](#code-conventions)
- [Debugging Tips](#debugging-tips)


## Repository Layout

```
SKTiled/
├── Package.swift            the package: SKTiled library + SKTiledTests
├── Sources/                 the library (one module); see How SKTiled Works
│   └── SKTiled.docc/        DocC catalog
├── Tests/
│   ├── *.swift              XCTest suites
│   ├── Assets/              the original test map and tilesets
│   └── Fixtures/            loader fixtures: nested/flattened layouts, JPEG, broken files
├── Demo/                    SwiftUI demo app (Xcode project); see Demo App
├── Docs/                    MkDocs sources for this site
├── mkdocs.yml               site configuration
├── requirements-docs.txt    Python packages for the site
└── scripts/
    ├── check.sh             all checks: tests, builds, docs
    └── build-docs.sh        MkDocs site + DocC API reference
```


## Toolchain

- **Xcode 26 or later**, selected with `xcode-select` (or `DEVELOPER_DIR`).
- **Use Xcode's Swift from the command line: `xcrun swift …`.** If a separate toolchain (for example one installed by swiftly) is first on `PATH`, plain `swift build` uses it, cannot find the Apple SDK frameworks, and fails with thousands of *"cannot find type 'CGFloat' in scope"* errors.
- **Python 3** for the documentation site, once per checkout:

    ```bash
    python3 -m venv .venv
    .venv/bin/pip install -r requirements-docs.txt
    export PATH="$PWD/.venv/bin:$PATH"
    ```

    `requirements-docs.txt` pins MkDocs below 2.0: MkDocs 2.0 drops the plugin and theme system the Material theme depends on.

**Xcode build location.** If Xcode's *Settings ▸ Locations ▸ Derived Data ▸ Advanced* is set to a custom, project-relative location, `xcodebuild` writes `Build/` folders next to the project and ignores `-derivedDataPath`. The scripts pass `SYMROOT`, `OBJROOT` and `SHARED_PRECOMPS_DIR` so their output always lands in `.build/`; do the same in your own `xcodebuild` commands. `Demo/Build/` is ignored by git for the same reason.


## Everyday Commands

| Task                                  | Command                                                                  |
|:--------------------------------------|:-------------------------------------------------------------------------|
| Build the library (macOS)             | `xcrun swift build`                                                      |
| Run the tests                         | `xcrun swift test`                                                       |
| Run one suite or test                 | `xcrun swift test --filter LoadingTests` / `--filter LoadingTests/testNestedTiledLayoutLoads` |
| Build for iOS or tvOS                 | `xcodebuild build -scheme SKTiled -destination 'generic/platform=iOS'` (or `tvOS`) |
| Everything before a commit            | `scripts/check.sh` (add `--no-docs` to skip the site)                     |
| Build the documentation site          | `scripts/build-docs.sh`, then open `site/index.html`                      |
| Preview the guides while editing      | `mkdocs serve` (the API reference is not served; build it with `build-docs.sh`) |
| Open the library in Xcode             | Open `Package.swift`, or the demo project, which includes the package    |

`scripts/check.sh` runs, and stops at the first failure:

1. `xcrun swift test` on macOS;
2. the library for macOS, iOS and tvOS;
3. the demo app for macOS, the iOS simulator and the tvOS simulator (without code signing);
4. `scripts/build-docs.sh` (strict MkDocs build, then DocC).

Builds are checked locally; there is no hosted CI.

**Working on the library and an app together.** Add the checkout to the app as a local package (**File ▸ Add Package Dependencies… ▸ Add Local…**). The app then builds SKTiled from source, so library edits take effect on the next run. The demo project is set up this way.


## Tests

The suites use XCTest and run on macOS. Test classes are `@MainActor`, because SKTiled is main-actor isolated, and set up with `override func setUp() async throws`.

| Suite                 | Covers                                                                                      |
|:----------------------|:--------------------------------------------------------------------------------------------|
| `LoadingTests`        | Folder layouts (nested, flattened), JPEG sprite sheets, `load(named:)` lookup, tileset reuse, every `TiledError` case, multi-map isolation, release of maps, debug drawing. Uses `Tests/Fixtures`. |
| `ParserTests`, `TilemapTests`, `TilesetTests` | Parsing and the map and tileset models, using `Tests/Assets/test-tilemap.tmx`. |
| `CoordinateTests`, `QueryTests`, `PropertiesTests` | Coordinate conversion, tile and object queries, custom properties.        |
| `CompressionTests`, `ColorTests` | Base64/zlib/gzip decoding, color parsing.                                        |
| `PerformanceTests`    | Load-time measurements (skipped when their maps are absent).                                 |

**Resources.** Test files are bundled by `Package.swift`: the files in `Tests/Assets` individually, and `Tests/Fixtures` as a whole folder (`.copy("Fixtures")`), which keeps its directory structure. In tests, find them with `Bundle.module`:

```swift
let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    .appendingPathComponent("nested/maps/level.tmx")
let tilemap = try SKTilemap.load(url: url, loggingLevel: .none)
```

**Adding a loader test.** Add the Tiled files under `Tests/Fixtures/<case>/` in the layout you want to test (new files there are picked up automatically), then a test to `LoadingTests`. For error cases, assert the exact `TiledError` case:

```swift
XCTAssertThrowsError(try load("errors/missing-image.tmx")) { error in
    guard case TiledError.imageNotFound(let source, _) = error else {
        return XCTFail("unexpected error: \(error)")
    }
    XCTAssertEqual(source, "does-not-exist.png")
}
```

Fixtures can be written by hand (TMX is XML); keep them small. The existing fixtures reuse the 8 × 8 pixel tilesets from `Tests/Assets`.

**Leaks and isolation.** When changing how nodes reference each other, keep `testMapIsReleasedWhenNoLongerReferenced` and `testEachMapCachesOnlyItsOwnTiles` passing; they catch retain cycles and state shared between maps.


## Documentation

| What                         | Where                                            | Built by                     |
|:-----------------------------|:-------------------------------------------------|:-----------------------------|
| Guides (this site)           | `Docs/*.md`, `Docs/developer/*.md`, `Docs/images/` | MkDocs (`mkdocs.yml`)        |
| API reference                | `///` comments in `Sources/`, plus `Sources/SKTiled.docc/` | DocC (`xcodebuild docbuild`) |
| Changes                      | `CHANGELOG.md`                                   | —                            |

`scripts/build-docs.sh` builds both into `site/`: the guides at the root and the API reference in `site/api/`. The DocC output is built for hosting at `/SKTiled/api` (GitHub Pages for the repository); set `HOSTING_BASE_PATH` to change it.

Rules the build enforces:

- **MkDocs runs in strict mode**: broken links between pages and missing anchors fail the build. Link to other pages with relative `.md` paths (`../working-with-maps.md#loading-a-tilemap`); anchors are the heading text in lowercase with spaces as hyphens and punctuation removed.
- **DocC warnings are errors** (`--warnings-as-errors`). A parameter documented with its external label instead of its internal name, a documented parameter that no longer exists, or an undocumented parameter all warn. Use internal parameter names in `- parameter` lines.
- New pages must be added to `nav` in `mkdocs.yml`; MkDocs only reports a page that is missing from it, so check the build output.


## Code Conventions

**Concurrency.** New code is main-actor isolated by default and should stay that way when it touches nodes. Mark code `nonisolated` only when it is pure value-type work (a new CoreGraphics or `String` helper, for example). Don't add `DispatchQueue` or `Task.detached` work that touches SpriteKit nodes. Don't write `deinit` cleanup; it can't reach main-actor state.

**Errors.** Loading code reports problems by throwing a `TiledError`. Inside the XML parser, call `fail(_:_:)` (it records the error and aborts parsing) and return. Never add `fatalError`, `try!` or force-unwraps on file contents: a malformed map must never crash an app. Parse attributes with `attributeDict["x"].flatMap { Int($0) }` and treat `nil` as invalid content.

**Ownership.** A reference from a child to its parent (tile → layer, layer → map, tileset → map) must be `weak`. Per-map state belongs to that map; don't use `NotificationCenter` with `object: nil` for internal communication, because every map receives every post.

**Overridable API.** Methods that subclasses should override must be declared in the class body (`open`), not in an extension: Swift members declared in extensions cannot be overridden.

**Platform clashes.** On iOS and tvOS, `SKNode` conforms to `UICoordinateSpace` and `UIFocusItem`. Don't give node subclasses members named `bounds`, `frame`, `center` or other names from those protocols; 1.x's `bounds` broke the iOS build.

**Documentation comments.** Use `///`. Document parameters with their internal names. Keep examples compiling against the current API.

**Dependencies.** The library uses only Apple frameworks (Foundation, SpriteKit, GameplayKit, ImageIO, zlib). Adding a third-party dependency needs a strong case.

**File headers.** New files carry the MIT license text used by the existing files.


## Debugging Tips

- **Loading.** Pass `loggingLevel: .debug` to see every file the parser reads, tilesets as they are built, and warnings for unknown tile IDs. A thrown `TiledError`'s `localizedDescription` names the file that failed and the file that referenced it.
- **What is in the bundle.** In a built app, check `Contents/Resources` (macOS) or the `.app` folder (iOS) for your maps' folder structure. A missing `.tsx` means the Tiled files weren't added as a folder reference; see [Creating a SwiftUI App](swiftui-app.md#4-add-your-tiled-files).
- **Visual debugging.** `tilemap.debugDrawOptions = [.drawGrid, .drawBounds]`, `tilemap.showObjects = true`, and `SpriteView`'s `debugOptions: [.showsFPS, .showsNodeCount, .showsDrawCount]`.
- **Map statistics.** `tilemap.dumpStatistics()` prints the map's layers and their contents.
- **Rendering every map.** Debug builds of the demo can render every bundled map to PNG and quit; see [Demo App: Snapshot Mode](demo-app.md#snapshot-mode).

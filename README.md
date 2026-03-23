# 🎬 PeekPro

**Instant Quick Look previews for Adobe Premiere Pro projects on macOS.**

Press Space on any `.prproj` file in Finder and see your timeline — tracks, clips, and label colors — without opening Premiere Pro.

![CI](https://github.com/asxrow66/PeekPro/actions/workflows/ci.yml/badge.svg)

---

## ✨ Features

- 🎨 **Timeline at a glance** — video and audio tracks rendered as a color-coded timeline
- 🏷️ **Accurate label colors** — reads your per-clip label assignments directly from the project file
- 🗂️ **Multi-sequence support** — tab between sequences when a project contains more than one
- 🚫 **No Premiere required** — works entirely offline with no dependency on Adobe software
- ⚡ **Fast** — parses and renders in milliseconds; gzip decompression is built in

---

## 🖥️ Requirements

| | |
|---|---|
| 🍎 **macOS** | 12 Monterey or later |
| 🎞️ **Premiere Pro** | Any version using the `.prproj` format |
| 🔨 **Xcode** | 15+ (to build from source) |

---

## 📦 Installation

> **📝 Note:** Because Quick Look extensions must be code-signed with an Apple Developer account, PeekPro is distributed as source code for you to build and install locally. Unsigned builds released via GitHub Actions are provided as a convenience — macOS Gatekeeper will block them unless you build with your own certificate.

### 🔧 Build from source (recommended)

```bash
# 1. Clone the repo
git clone https://github.com/asxrow66/PeekPro.git
cd PeekPro

# 2. Open in Xcode (handles signing automatically with your Apple ID)
make open

# 3. Build & install  (Xcode → Product → Build, then run make install)
make install TEAM=<YourTeamID>
```

Your Team ID is visible in **Xcode → Settings → Accounts → select your Apple ID → Team ID column**.

### ✅ After installing

```bash
# Register the extension and restart Quick Look
pluginkit -a /Applications/PeekPro.app/Contents/PlugIns/PremiereQuickLookExtension.appex
qlmanage -r
```

Then press **Space** on any `.prproj` file in Finder. 🎉

---

## 🔍 How It Works

`.prproj` files are gzip-compressed XML. PeekPro:

1. 📂 Decompresses the file in-process using `zlib`
2. 🔎 Streams the XML with `XMLParser` — no full DOM in memory
3. 🔗 Resolves the object-reference graph (Sequence → TrackGroups → Tracks → ClipTrackItems → SubClips → VideoClips)
4. 🏷️ Reads `asl.clip.label.name` (slot key) and `asl.clip.label.color` (BGR-encoded snapshot) for each clip
5. 🗺️ Builds a per-slot color map from project-panel clips (via `MasterClip` references) to get canonical label colors, falling back to Premiere's 16 default label colors
6. 🖼️ Renders the timeline with Core Graphics — no WebKit, no AppKit views beyond a single `NSView`

---

## 🛠️ Building & Development

```bash
# Generate the Xcode project from project.yml (requires xcodegen)
make generate

# Build unsigned (for CI / local testing without a certificate)
xcodebuild \
  -project PremiereProTimelineQuickLook.xcodeproj \
  -scheme PremiereProTimelineQuickLook \
  -configuration Release \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

# Reset Quick Look daemon after a build
make reset-ql
```

---

## 📁 Project Structure

```
PeekPro/
├── 📄 project.yml                        # XcodeGen project spec
├── 🔨 Makefile                           # Build / install helpers
├── 📱 PremiereQuickLookApp/              # Minimal host app (required by macOS)
│   └── AppDelegate.swift
└── 🔌 PremiereQuickLookExtension/        # The Quick Look extension
    ├── Models.swift                      # Data models + label color definitions
    ├── ProjectParser.swift               # XML parser & object-graph resolver
    └── PreviewViewController.swift       # Core Graphics timeline renderer
```

---

## 📄 License

MIT — see [LICENSE](LICENSE).

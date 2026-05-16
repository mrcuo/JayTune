# JayTune 🎵

<img src="https://img.shields.io/badge/macOS-14.0+-blue?style=flat&logo=apple" alt="macOS 14.0+">
<img src="https://img.shields.io/badge/Swift-5.9+-orange?style=flat&logo=swift">
<img src="https://img.shields.io/badge/UI-SwiftUI-green?style=flat">
<img src="https://img.shields.io/github/license/mrcuo/JayTune?style=flat">
<img src="https://img.shields.io/github/stars/mrcuo/JayTune?style=flat">

**JayTune** is a modern macOS application for managing iPod music libraries. It provides a beautiful SwiftUI interface to browse, organize, and transfer music from your iPod classic/nano/touch devices.

> 🎯 **Mission**: Bridge the gap between legacy iPod devices and modern macOS systems.

---

## ✨ Features

### 📱 Device Management
- **Automatic Device Detection** - Plug-and-play iPod detection via USB
- **Device Information** - View storage capacity, iOS version, and device details
- **Real-time Status** - Live connection status monitoring

### 🎶 Music Library
- **Smart Scanning** - Efficiently scans iPod's iTunesDB to extract music metadata
- **Rich Metadata** - Displays title, artist, album, genre, duration, bitrate, and more
- **File Path Mapping** - Locates actual music files on the iPod filesystem

### 📂 Organization
- **Multiple Views**:
  - 📜 **Songs** - Flat list of all tracks with sorting and search
  - 💿 **Albums** - Grouped by album with artwork placeholders
  - 🎤 **Artists** - Grouped by artist for easy browsing
  - 📋 **Playlists** - (Coming soon) Manage and create playlists

### 🔧 Advanced Features
- **Import/Export** - Transfer music between iPod and Mac
- **Metadata Editing** - Modify track information (planned)
- **Smart Playlists** - Create dynamic playlists based on rules (planned)

---

## 📸 Screenshots

<!-- TODO: Add screenshots when available -->
<!-- ![Main Interface](screenshots/main.png) -->
<!-- ![Album View](screenshots/albums.png) -->

*Screenshots coming soon...*

---

## 🚀 Getting Started

### System Requirements
- macOS 14.0 (Sonoma) or later
- iPod classic, nano, shuffle, or touch (any generation)
- USB cable for iPod connection
- [Homebrew](https://brew.sh/) package manager

### Prerequisites

JayTune requires `libimobiledevice` for iPod communication:

```bash
# Install libimobiledevice
brew install libimobiledevice

# Verify installation
idevice_id -l
```

### Installation

#### Option 1: Download Release (Recommended)
1. Go to [Releases](https://github.com/mrcuo/JayTune/releases)
2. Download the latest `JayTune.app.zip`
3. Unzip and move `JayTune.app` to your Applications folder
4. On first launch, right-click the app and select "Open" (due to unsigned app)

#### Option 2: Build from Source
```bash
# Clone the repository
git clone https://github.com/mrcuo/JayTune.git
cd JayTune

# Build the project
./build.sh

# The app will be created at ./JayTune.app
# You can also find it in the DerivedData folder
```

---

## 📖 Usage Guide

### 1. Connect Your iPod
- Launch JayTune
- Connect your iPod via USB cable
- The app will automatically detect the device
- Wait for the "Connected" status

### 2. Browse Your Music
- **Songs Tab**: View all tracks in a sortable list
- **Albums Tab**: Browse by album with grouped sections
- **Artists Tab**: Explore by artist name
- Use the search bar to filter tracks in real-time

### 3. Import/Export Music
- Click "Import" to add music from your Mac to iPod
- Select tracks and click "Export" to save them to your Mac
- Progress bar shows transfer status

### 4. Refresh Library
- Click the "Refresh" button to rescan the iPod
- Useful after manually adding music via other tools

---

## 🏗️ Architecture

### Tech Stack
| Component | Technology |
|-----------|------------|
| UI Framework | SwiftUI |
| Device Communication | AFC Protocol via `libimobiledevice` |
| Metadata Parsing | iTunesDB Parser (custom) |
| File System Access | `afc_ls`, `afc_read2` tools |
| Audio Metadata | `ffprobe` (optional) |

### Project Structure
```
JayTune/
├── JayTune.xcodeproj/          # Xcode project (if using Xcode)
├── JayTune/
│   ├── JayTuneApp.swift        # App entry point
│   ├── ContentView.swift      # Main UI view
│   ├── DeviceManager.swift    # iPod detection & communication
│   ├── Models/
│   │   └── MusicTrack.swift  # Track data model
│   ├── Views/
│   │   ├── MusicListView.swift   # Songs list view
│   │   ├── AlbumView.swift      # Albums grouped view
│   │   └── ArtistView.swift     # Artists grouped view
│   ├── Resources/
│   │   └── JayTune.entitlements
│   └── Tools/
│       ├── afc_ls             # AFC file listing tool
│       └── afc_read2         # AFC file reading tool
├── JayTuneTests/
│   └── JayTuneTests.swift    # Unit tests
├── build.sh                  # Build script
└── Package.swift             # SPM manifest (if applicable)
```

---

## ⚙️ How It Works

JayTune uses the **Apple File Conduit (AFC)** protocol to communicate with iPod devices:

1. **Device Detection**:
   - Uses `idevice_id -l` to list connected device UDIDs
   - Uses `ideviceinfo` to fetch device details

2. **Music Library Scanning**:
   - Accesses `/iTunes_Control/Music/` via AFC
   - Parses iTunesDB files to extract track metadata
   - Maps track IDs to actual file paths

3. **File Operations**:
   - `afc_ls` lists files in iPod directories
   - `afc_read2` reads file contents from iPod
   - Supports bidirectional file transfer

---

## 🛠️ Development

### Build Instructions
```bash
# Full build with notarization (if signed)
./build.sh

# The script will:
# 1. Compile Swift sources using xcrun swiftc
# 2. Package into JayTune.app
# 3. Codesign the app (ad-hoc if no certificate)
# 4. Create a zip for distribution
```

### Key Files for Developers
- **DeviceManager.swift**: Core logic for iPod communication
- **ContentView.swift**: Main UI structure and navigation
- **MusicTrack.swift**: Data model with iTunesDB field mappings

### Debugging Tips
- Enable logging in `DeviceManager.swift` by setting `debugMode = true`
- Check Console.app for system logs filtered by "JayTune"
- Use `idevice_id -l` and `ideviceinfo` to verify device connectivity

---

## 🐛 Known Issues

- [ ] Playlist view shows "Coming soon" (not yet implemented)
- [ ] Large libraries (>5000 tracks) may take time to scan
- [ ] Unsigned app requires manual "Open" on first launch
- [ ] iPod shuffle support is experimental

---

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/AmazingFeature`)
3. **Commit** your changes (`git commit -m 'Add some AmazingFeature'`)
4. **Push** to the branch (`git push origin feature/AmazingFeature`)
5. **Open a Pull Request**

### Development Guidelines
- Follow Swift API Design Guidelines
- Use SwiftUI best practices
- Add unit tests for new features
- Update documentation as needed

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- [libimobiledevice](https://libimobiledevice.org/) - Open-source library for iOS device communication
- [SwiftUI](https://developer.apple.com/xcode/swiftui/) - Apple's declarative UI framework
- [iTunesDB Documentation](https://www.rockbox.org/wiki/iTunesDBFormat) - Rockbox project's documentation on iTunes database format

---

## 📧 Contact

**Zhang Yajie (张亚杰)**
- GitHub: [@mrcuo](https://github.com/mrcuo)
- Project Link: [https://github.com/mrcuo/JayTune](https://github.com/mrcuo/JayTune)

---

## 🔮 Roadmap

- [x] Basic iPod detection and music scanning
- [x] Songs/Albums/Artists views
- [ ] Playlist management
- [ ] Music playback (preview tracks)
- [ ] Batch metadata editing
- [ ] Smart playlist creator
- [ ] iPod backup and restore
- [ ] Support for multiple iPods simultaneously

---

<div align="center">
  <p>Made with ❤️ for iPod lovers everywhere</p>
  <p>⭐ Star this repo if you find it useful!</p>
</div>

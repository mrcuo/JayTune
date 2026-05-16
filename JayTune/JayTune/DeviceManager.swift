import Foundation

// MARK: - 启动日志（帮助诊断闪退）
private func bootstrapLog(_ msg: String) {
    print("[Bootstrap] \(msg)")
    let path = "/tmp/jaytune_bootstrap.log"
    let line = "[\(Date())] \(msg)\n"
    let fm = FileManager.default
    if fm.fileExists(atPath: path),
       let fh = try? FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// MARK: - 设备模型
struct iPodDevice: Identifiable, Hashable {
    let id = UUID()
    let udid: String
    let name: String
    let iOSVersion: String
    let productType: String
    let totalCapacity: Int64
    let freeSpace: Int64

    func hash(into hasher: inout Hasher) { hasher.combine(udid) }
    static func == (lhs: iPodDevice, rhs: iPodDevice) -> Bool { lhs.udid == rhs.udid }

    var usedSpace: Int64 { totalCapacity - freeSpace }
    var usedPercent: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedSpace) / Double(totalCapacity) * 100
    }
}

// MARK: - 设备管理器（支持多设备发现与选择）
class DeviceManager: ObservableObject {
    // 必须在 useWiFi 之前初始化，阻止 init 期间触发 refreshDevices
    private var isInitializing = true

    @Published var isConnected: Bool = false
    @Published var discoveredDevices: [iPodDevice] = []
    @Published var selectedDevice: iPodDevice?
    @Published var connectionStatus: String = ""
    @Published var tracks: [MusicTrack] = []

    // 导出/删除状态
    @Published var isBusy: Bool = false
    @Published var busyMessage: String = ""
    @Published var busyProgress: Double = 0

    // 连接模式
    @Published var useWiFi: Bool {
        didSet {
            UserDefaults.standard.set(useWiFi, forKey: "jaytune_use_wifi")
            guard !isInitializing else { return }
            refreshDevices()
        }
    }

    // 当前实际连接方式
    @Published var activeConnectionMode: String = ""

    // 多设备选择 Sheet
    @Published var showingDevicePicker: Bool = false

    static let shared = DeviceManager()

    private let ideviceIdPath = "/opt/homebrew/bin/idevice_id"
    private let ideviceInfoPath = "/opt/homebrew/bin/ideviceinfo"

    private init() {
        bootstrapLog("DeviceManager.init() 开始")
        // 先设默认值，避免在非主线程访问 L10n
        connectionStatus = "正在检测设备..."
        let savedWiFi = UserDefaults.standard.object(forKey: "jaytune_use_wifi") as? Bool ?? false
        bootstrapLog("useWiFi 读取: \(savedWiFi)")
        self.useWiFi = savedWiFi
        // 初始化完成，允许 didSet 触发刷新
        self.isInitializing = false
        bootstrapLog("DeviceManager.init() 完成，isInitializing=false")
    }

    // MARK: - 构建工具参数
    private func afcArgs(_ baseArgs: [String]) -> [String] {
        activeConnectionMode == "wifi" ? ["-n"] + baseArgs : baseArgs
    }

    // MARK: - 设备发现（支持 USB/WiFi 双模式和自动回退）
    func refreshDevices() {
        bootstrapLog("refreshDevices() 开始")
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            bootstrapLog("refreshDevices() 进入后台线程")

            var triedModes: [(mode: String, useNetwork: Bool)] = []
            if self.useWiFi {
                triedModes = [("wifi", true), ("usb", false)]
            } else {
                triedModes = [("usb", false), ("wifi", true)]
            }

            bootstrapLog("refreshDevices() 开始尝试模式: \(triedModes.map { $0.mode })")

            var allDevices: [(device: iPodDevice, mode: String)] = []

            for (modeName, useNetwork) in triedModes {
                bootstrapLog("refreshDevices() 尝试 \(modeName) 模式")
                let args = useNetwork ? ["-n", "-l"] : ["-l"]
                let output = self.runCommand(self.ideviceIdPath, args: args)
                bootstrapLog("idevice_id 输出: \(output.prefix(200))")
                let udids = output
                    .components(separatedBy: "\n")
                    .map { line in
                        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if useNetwork {
                            trimmed = trimmed.replacingOccurrences(of: " (Network)", with: "")
                        }
                        return trimmed
                    }
                    .filter { !$0.isEmpty && $0.count >= 10 }

                for udid in udids {
                    let infoArgs = useNetwork ? ["-n", "-u", udid] : ["-u", udid]
                    let infoOutput = self.runCommand(self.ideviceInfoPath, args: infoArgs)
                    let fields = self.parseInfoOutput(infoOutput)

                    _ = fields["DeviceClass"] ?? ""
                    // 只显示 iPod 设备（可选，若需要支持 iPhone/iPad 可去掉此过滤）
                    // if deviceClass != "iPod" && !deviceClass.isEmpty { continue }

                    let productType = fields["ProductType"] ?? ""
                    let name = fields["DeviceName"] ?? "iPod touch"
                    let version = fields["ProductVersion"] ?? ""
                    let capacityStr = fields["TotalDataCapacity"] ?? ""
                    let freeStr = fields["TotalDataAvailable"] ?? ""

                    let total = self.parseBytes(capacityStr) ?? 32_000_000
                    let free = self.parseBytes(freeStr) ?? 8_000_000

                    let device = iPodDevice(
                        udid: udid,
                        name: name,
                        iOSVersion: version,
                        productType: productType,
                        totalCapacity: total,
                        freeSpace: free
                    )

                    // 去重（同一台设备可能同时出现在 USB 和网络）
                    if !allDevices.contains(where: { $0.device.udid == udid }) {
                        allDevices.append((device, modeName))
                    }
                }
            }

            guard !allDevices.isEmpty else {
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.discoveredDevices = []
                    self.selectedDevice = nil
                    self.activeConnectionMode = ""
                    self.connectionStatus = L10n.shared.localized("device.not_found_wifi_hint")
                }
                return
            }

            // 同步到主线程
            DispatchQueue.main.async {
                self.discoveredDevices = allDevices.map { $0.device }

                if allDevices.count == 1 {
                    // 只有一台设备，自动选择
                    let (device, modeName) = allDevices[0]
                    self.selectDevice(device, mode: modeName)
                } else {
                    // 多台设备，若当前没有选中设备则弹出选择器
                    if self.selectedDevice == nil {
                        self.showingDevicePicker = true
                        self.connectionStatus = String(format: L10n.shared.localized("device.multiple_found"), allDevices.count)
                    } else {
                        // 已选中设备，仅更新连接模式
                        if let existing = allDevices.first(where: { $0.device.udid == self.selectedDevice?.udid }) {
                            self.activeConnectionMode = existing.mode
                        }
                        self.isConnected = true
                    }
                }
            }
        }
    }

    // MARK: - 选择指定设备
    func selectDevice(_ device: iPodDevice, mode: String? = nil) {
        let targetMode = mode ?? activeConnectionMode
        self.selectedDevice = device
        self.activeConnectionMode = targetMode
        self.isConnected = true

        let modeLabel = targetMode == "wifi" ? "📶 Wi-Fi" : "🔌 USB"
        self.connectionStatus = "\(device.name) (iOS \(device.iOSVersion)) \(L10n.shared.localized("device.connected")) · \(modeLabel)"

        // 同步 useWiFi 偏好
        if targetMode == "wifi" && !self.useWiFi {
            self.useWiFi = true
        }

        // 自动加载音乐库
        self.loadMusicLibrary()
    }

    // MARK: - 读取音乐库
    func loadMusicLibrary() {
        guard let device = selectedDevice else { return }
        let udid = device.udid
        let toolsDir = bundleToolsDir()
        let afcLs = "\(toolsDir)/afc_ls"
        let afcRead = "\(toolsDir)/afc_read2"
        let ffprobe = "/opt/homebrew/bin/ffprobe"

        DispatchQueue.global(qos: .userInitiated).async {
            let dirsOutput = self.runCommand(afcLs, args: self.afcArgs([udid, "/iTunes_Control/Music"]))
            let dirs = dirsOutput
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.range(of: #"^F\d+$"#, options: .regularExpression) != nil }

            guard !dirs.isEmpty else {
                DispatchQueue.main.async {
                    self.tracks = []
                    self.connectionStatus = L10n.shared.localized("device.no_music")
                }
                return
            }

            DispatchQueue.main.async {
                self.connectionStatus = L10n.shared.localized("device.scanning", dirs.count)
            }

            var allTracks: [MusicTrack] = []

            for dir in dirs {
                let filesOutput = self.runCommand(afcLs, args: self.afcArgs([udid, "/iTunes_Control/Music/\(dir)"]))
                let files = filesOutput
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.lowercased().hasSuffix(".m4a") || $0.lowercased().hasSuffix(".mp3") }

                for file in files {
                    let remotePath = "/iTunes_Control/Music/\(dir)/\(file)"
                    let tmpFile = "/tmp/jaytune_\(UUID().uuidString)"

                    _ = self.runCommand(afcRead, args: self.afcArgs([udid, remotePath]), stdoutPath: tmpFile)

                    if FileManager.default.fileExists(atPath: tmpFile),
                       let attrs = try? FileManager.default.attributesOfItem(atPath: tmpFile),
                       (attrs[.size] as? UInt64 ?? 0) > 1000 {

                        let jsonStr = self.runCommand(ffprobe, args: [
                            "-v", "quiet",
                            "-print_format", "json",
                            "-show_format",
                            tmpFile
                        ])

                        if let data = jsonStr.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let fmt = json["format"] as? [String: Any],
                           let tags = fmt["tags"] as? [String: String] {

                            let title = tags["title"] ?? file.replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression)
                            let artist = tags["artist"] ?? L10n.shared.localized("import.unknown_artist")
                            let album = tags["album"] ?? L10n.shared.localized("import.unknown_album")
                            let genre = tags["genre"] ?? ""
                            let durationMs = Int((fmt["duration"] as? Double ?? 0) * 1000)
                            let fileSize = attrs[.size] as? UInt32 ?? 0
                            let trackNum = Int(tags["track"]?.components(separatedBy: "/").first ?? "0") ?? 0

                            let track = MusicTrack(
                                id: UInt32(allTracks.count + 1),
                                title: title,
                                artist: artist,
                                album: album,
                                genre: genre,
                                filePath: remotePath.dropFirst().replacingOccurrences(of: "/", with: ":"),
                                trackNumber: UInt32(max(1, trackNum)),
                                duration: UInt32(durationMs),
                                fileSize: fileSize
                            )
                            allTracks.append(track)
                        }
                    }
                    try? FileManager.default.removeItem(atPath: tmpFile)
                }

                let completed = allTracks.count
                DispatchQueue.main.async {
                    self.connectionStatus = String(format: L10n.shared.localized("device.scan_progress"), dirs.firstIndex(of: dir)! + 1, dirs.count, completed)
                }
            }

            DispatchQueue.main.async {
                self.tracks = allTracks.sorted { $0.artist == $1.artist ? $0.album < $1.album : $0.artist < $1.artist }
                self.connectionStatus = String(format: L10n.shared.localized("device.scan_complete"), device.name, allTracks.count)
            }
        }
    }

    // MARK: - Helper: 获取 Tools 目录路径
    private func bundleToolsDir() -> String {
        guard let bundlePath = Bundle.main.resourcePath else { return "/tmp" }
        return (bundlePath as NSString).appendingPathComponent("Tools")
    }

    // MARK: - Helper: 运行命令
    private func runCommand(_ path: String, args: [String], stdoutPath: String? = nil) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args

        if let outPath = stdoutPath {
            if !FileManager.default.fileExists(atPath: outPath) {
                FileManager.default.createFile(atPath: outPath, contents: nil)
            }
            guard let outHandle = FileHandle(forWritingAtPath: outPath) else {
                return ""
            }
            task.standardOutput = outHandle
            task.standardError = Pipe()

            do {
                try task.run()
                task.waitUntilExit()
                outHandle.closeFile()
                return ""
            } catch {
                outHandle.closeFile()
                return ""
            }
        } else {
            let pipe = Pipe()
            let errPipe = Pipe()
            task.standardOutput = pipe
            task.standardError = errPipe

            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8) ?? ""
            } catch {
                return ""
            }
        }
    }

    // MARK: - Helper: 解析 ideviceinfo 输出
    private func parseInfoOutput(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                result[key] = value
            }
        }
        return result
    }

    // MARK: - Helper: 解析字节数
    private func parseBytes(_ str: String) -> Int64? {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        if let num = Int64(trimmed) { return num }

        let parts = trimmed.components(separatedBy: " ")
        if parts.count >= 1, let num = Int64(parts[0]) {
            if parts.count >= 2 {
                let unit = parts[1].uppercased()
                if unit.contains("GB") { return num * 1_000_000_000 }
                if unit.contains("MB") { return num * 1_000_000 }
            }
        }
        return nil
    }

    // MARK: - ===== 导出功能 =====

    func exportTrack(_ track: MusicTrack, to directoryURL: URL) {
        guard let device = selectedDevice else { return }
        isBusy = true

        DispatchQueue.global(qos: .userInitiated).async {
            let toolsDir = self.bundleToolsDir()
            let afcRead = "\(toolsDir)/afc_read2"
            let remotePath = "/" + track.filePath.replacingOccurrences(of: ":", with: "/")
            let destURL = directoryURL.appendingPathComponent(track.exportFilename)

            self.busyMessage = L10n.shared.localized("export.progress", track.title)
            self.busyProgress = 0

            _ = self.runCommand(afcRead, args: self.afcArgs([device.udid, remotePath]), stdoutPath: destURL.path)

            DispatchQueue.main.async {
                if FileManager.default.fileExists(atPath: destURL.path),
                   let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path),
                   (attrs[.size] as? UInt64 ?? 0) > 1000 {
                    self.busyMessage = L10n.shared.localized("export.complete", track.title)
                } else {
                    self.busyMessage = L10n.shared.localized("export.failed", track.title)
                }
                self.busyProgress = 1.0
                self.isBusy = false
            }
        }
    }

    func exportTracks(_ tracksToExport: [MusicTrack], to directoryURL: URL) {
        guard !tracksToExport.isEmpty else { return }
        isBusy = true
        busyProgress = 0

        DispatchQueue.global(qos: .userInitiated).async {
            for (index, track) in tracksToExport.enumerated() {
                let progress = Double(index) / Double(tracksToExport.count)

                DispatchQueue.main.async {
                    self.busyMessage = String(format: L10n.shared.localized("export.batch_progress"), index + 1, tracksToExport.count, track.title)
                    self.busyProgress = progress
                }

                let toolsDir = self.bundleToolsDir()
                let afcRead = "\(toolsDir)/afc_read2"
                guard let device = self.selectedDevice else { break }
                let remotePath = "/" + track.filePath.replacingOccurrences(of: ":", with: "/")
                let destURL = directoryURL.appendingPathComponent(track.exportFilename)

                _ = self.runCommand(afcRead, args: self.afcArgs([device.udid, remotePath]), stdoutPath: destURL.path)
            }

            DispatchQueue.main.async {
                self.busyMessage = L10n.shared.localized("export.batch_complete", tracksToExport.count)
                self.busyProgress = 1.0
                self.isBusy = false
            }
        }
    }

    // MARK: - ===== 删除功能 =====

    func deleteTracks(_ tracksToDelete: [MusicTrack]) {
        guard !tracksToDelete.isEmpty, let device = selectedDevice else { return }

        isBusy = true
        busyProgress = 0

        DispatchQueue.global(qos: .userInitiated).async {
            let toolsDir = self.bundleToolsDir()
            let afcRm = "\(toolsDir)/afc_rm"
            var deletedIDs: Set<UInt32> = []

            for (index, track) in tracksToDelete.enumerated() {
                let progress = Double(index) / Double(tracksToDelete.count)
                DispatchQueue.main.async {
                    self.busyMessage = String(format: L10n.shared.localized("delete.progress"), index + 1, tracksToDelete.count, track.title)
                    self.busyProgress = progress
                }

                let remotePath = "/" + track.filePath.replacingOccurrences(of: ":", with: "/")
                let output = self.runCommand(afcRm, args: self.afcArgs([device.udid, remotePath]))
                if output.contains("OK:") || output.isEmpty {
                    deletedIDs.insert(track.id)
                }
            }

            DispatchQueue.main.async {
                self.tracks.removeAll { deletedIDs.contains($0.id) }
                self.busyMessage = L10n.shared.localized("delete.complete", deletedIDs.count)
                self.busyProgress = 1.0
                self.isBusy = false
            }
        }
    }
}

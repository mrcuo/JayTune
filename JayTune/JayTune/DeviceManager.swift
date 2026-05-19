import Foundation

// MARK: - 启动日志（帮助诊断闪退）
private func bootstrapLog(_ msg: String) {
    print("[Bootstrap] \(msg)")
    let path = "/tmp/jaytune_bootstrap.log"
    let line = "[\(Date())] \(msg)\n"
    let fm = FileManager.default
    if fm.fileExists(atPath: path),
       let fh = FileHandle(forWritingAtPath: path) {
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

    // 导出/删除/导入状态
    @Published var isBusy: Bool = false
    @Published var busyMessage: String = ""
    @Published var busyProgress: Double = 0

    // 导入状态
    @Published var isImporting: Bool = false

    // 取消标志
    @Published var isScanning: Bool = false
    private var scanCancelled: Bool = false

    // 扫描互斥锁：防止重复触发扫描
    private var isScanRunning: Bool = false

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

    // MARK: - 取消当前扫描
    func cancelScan() {
        scanCancelled = true
        // 杀掉卡住的 afc_read2 进程，让扫描线程能快速退出
        killStaleAfcProcesses()
    }

    // MARK: - 读取音乐库
    func loadMusicLibrary() {
        guard let device = selectedDevice else { return }

        // 扫描互斥：防止重复触发
        guard !isScanRunning else {
            bootstrapLog("loadMusicLibrary: 扫描正在进行，跳过")
            return
        }
        isScanRunning = true

        let udid = device.udid
        let toolsDir = bundleToolsDir()
        let afcLs = "\(toolsDir)/afc_ls"
        let afcHead = "\(toolsDir)/afc_head"
        let ffprobe = "/opt/homebrew/bin/ffprobe"

        // 杀掉残留的 afc_read2 进程（避免多个进程争抢 AFC 连接）
        killStaleAfcProcesses()

        // 清理上次扫描残留的临时文件
        cleanupTempFiles()

        // 重置取消标志
        scanCancelled = false
        DispatchQueue.main.async {
            self.isScanning = true
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            defer {
                self.isScanRunning = false
            }

            let dirsOutput = self.runCommand(afcLs, args: self.afcArgs([udid, "/iTunes_Control/Music"]), timeout: 30)
            let dirs = dirsOutput
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.range(of: #"^F\d+$"#, options: .regularExpression) != nil }

            guard !dirs.isEmpty else {
                DispatchQueue.main.async {
                    self.tracks = []
                    self.connectionStatus = L10n.shared.localized("device.no_music")
                    self.isScanning = false
                }
                return
            }

            DispatchQueue.main.async {
                self.connectionStatus = L10n.shared.localized("device.scanning", dirs.count)
            }

            var allTracks: [MusicTrack] = []

            for (dirIndex, dir) in dirs.enumerated() {
                // 检查取消
                if self.scanCancelled {
                    DispatchQueue.main.async {
                        self.connectionStatus = L10n.shared.localized("device.scan_complete", device.name, allTracks.count)
                        self.isScanning = false
                        self.scanCancelled = false
                    }
                    return
                }

                let filesOutput = self.runCommand(afcLs, args: self.afcArgs([udid, "/iTunes_Control/Music/\(dir)"]), timeout: 30)
                let files = filesOutput
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.lowercased().hasSuffix(".m4a") || $0.lowercased().hasSuffix(".mp3") }

                for file in files {
                    // 检查取消
                    if self.scanCancelled {
                        DispatchQueue.main.async {
                            self.connectionStatus = L10n.shared.localized("device.scan_complete", device.name, allTracks.count)
                            self.isScanning = false
                            self.scanCancelled = false
                        }
                        return
                    }

                    let remotePath = "/iTunes_Control/Music/\(dir)/\(file)"
                    let tmpFile = "/tmp/jaytune_\(UUID().uuidString)"

                    // 扫描时只读文件头 128KB（afc_head），用于 ffprobe 提取元数据
                    // 128KB 覆盖绝大多数 M4A 的 moov atom 位置（少数文件在 64KB~128KB 之间）
                    // 完整文件传输仅在导出时通过 afc_read2 进行
                    _ = self.runCommand(afcHead, args: self.afcArgs(["-b", "131072", udid, remotePath]), stdoutPath: tmpFile, timeout: 15)

                    if FileManager.default.fileExists(atPath: tmpFile),
                       let attrs = try? FileManager.default.attributesOfItem(atPath: tmpFile),
                       (attrs[.size] as? UInt64 ?? 0) > 1000 {

                        let jsonStr = self.runCommand(ffprobe, args: [
                            "-v", "quiet",
                            "-print_format", "json",
                            "-show_format",
                            tmpFile
                        ], timeout: 15)

                        var trackAdded = false
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
                            trackAdded = true
                        }

                        // 没有 tags 的曲目也收录（用文件名代替标题）
                        if !trackAdded {
                            let title = file.replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression)
                            let fileSize = attrs[.size] as? UInt32 ?? 0
                            let track = MusicTrack(
                                id: UInt32(allTracks.count + 1),
                                title: title,
                                artist: L10n.shared.localized("import.unknown_artist"),
                                album: L10n.shared.localized("import.unknown_album"),
                                filePath: remotePath.dropFirst().replacingOccurrences(of: "/", with: ":"),
                                fileSize: fileSize
                            )
                            allTracks.append(track)
                        }
                    }
                    try? FileManager.default.removeItem(atPath: tmpFile)
                }

                let completed = allTracks.count
                DispatchQueue.main.async {
                    self.connectionStatus = String(format: L10n.shared.localized("device.scan_progress"), dirIndex + 1, dirs.count, completed)
                }
            }

            DispatchQueue.main.async {
                self.tracks = allTracks.sorted { $0.artist == $1.artist ? $0.album < $1.album : $0.artist < $1.artist }
                self.connectionStatus = String(format: L10n.shared.localized("device.scan_complete"), device.name, allTracks.count)
                self.isScanning = false
            }
        }
    }

    // MARK: - 清理残留临时文件
    private func cleanupTempFiles() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: "/tmp") else { return }
        for item in contents where item.hasPrefix("jaytune_") {
            try? fm.removeItem(atPath: "/tmp/\(item)")
        }
    }

    // MARK: - 杀掉残留的 afc_read2 进程
    private func killStaleAfcProcesses() {
        // 用 pkill 杀掉所有残留的 afc_read2 进程，避免多个进程争抢 AFC 连接
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-f", "afc_read2"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
    }

    // MARK: - Helper: 获取 Tools 目录路径
    private func bundleToolsDir() -> String {
        guard let bundlePath = Bundle.main.resourcePath else { return "/tmp" }
        return (bundlePath as NSString).appendingPathComponent("Tools")
    }

    // MARK: - Helper: 运行命令（支持超时）
    private func runCommand(_ path: String, args: [String], stdoutPath: String? = nil, timeout: TimeInterval = 0) -> String {
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

                if timeout > 0 {
                    // 带超时的等待
                    let deadline = Date().addingTimeInterval(timeout)
                    while task.isRunning && Date() < deadline {
                        Thread.sleep(forTimeInterval: 0.2)
                    }
                    if task.isRunning {
                        bootstrapLog("runCommand TIMEOUT(\(timeout)s): \(path) \(args)")
                        task.terminate()
                        Thread.sleep(forTimeInterval: 0.5)
                        outHandle.closeFile()
                        return ""
                    }
                } else {
                    task.waitUntilExit()
                }
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

                if timeout > 0 {
                    let deadline = Date().addingTimeInterval(timeout)
                    while task.isRunning && Date() < deadline {
                        Thread.sleep(forTimeInterval: 0.2)
                    }
                    if task.isRunning {
                        bootstrapLog("runCommand TIMEOUT(\(timeout)s): \(path) \(args)")
                        task.terminate()
                        Thread.sleep(forTimeInterval: 0.5)
                        return ""
                    }
                } else {
                    task.waitUntilExit()
                }
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

        DispatchQueue.main.async {
            self.isBusy = true
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let toolsDir = self.bundleToolsDir()
            let afcRead = "\(toolsDir)/afc_read2"
            let remotePath = "/" + track.filePath.replacingOccurrences(of: ":", with: "/")
            let destURL = directoryURL.appendingPathComponent(track.exportFilename)

            DispatchQueue.main.async {
                self.busyMessage = L10n.shared.localized("export.progress", track.title)
                self.busyProgress = 0
            }

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

        DispatchQueue.main.async {
            self.isBusy = true
            self.busyProgress = 0
        }

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

    // MARK: - ===== 导入功能 =====

    /// 导入本地音乐文件到设备
    func importTracks(_ urls: [URL]) {
        guard let device = selectedDevice else {
            DispatchQueue.main.async {
                self.busyMessage = L10n.shared.localized("import.no_device")
                self.isBusy = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.isBusy = false
                }
            }
            return
        }

        DispatchQueue.main.async {
            self.isBusy = true
            self.isImporting = true
            self.busyProgress = 0
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 1. 递归收集所有 .m4a/.mp3 文件
            var audioFiles: [URL] = []
            for url in urls {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        // 递归遍历文件夹
                        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                            for case let fileURL as URL in enumerator {
                                let ext = fileURL.pathExtension.lowercased()
                                if ext == "m4a" || ext == "mp3" {
                                    audioFiles.append(fileURL)
                                }
                            }
                        }
                    } else {
                        let ext = url.pathExtension.lowercased()
                        if ext == "m4a" || ext == "mp3" {
                            audioFiles.append(url)
                        }
                    }
                }
            }

            guard !audioFiles.isEmpty else {
                DispatchQueue.main.async {
                    self.busyMessage = L10n.shared.localized("import.unsupported_format")
                    self.busyProgress = 1.0
                    self.isBusy = false
                    self.isImporting = false
                }
                return
            }

            let toolsDir = self.bundleToolsDir()
            let afcWrite = "\(toolsDir)/afc_write"
            let ffprobe = "/opt/homebrew/bin/ffprobe"
            let udid = device.udid
            var importedTracks: [MusicTrack] = []
            var failedCount: Int = 0

            for (index, url) in audioFiles.enumerated() {
                let progress = Double(index) / Double(audioFiles.count)

                DispatchQueue.main.async {
                    self.busyMessage = String(format: L10n.shared.localized("import.batch_progress"), index + 1, audioFiles.count, url.lastPathComponent)
                    self.busyProgress = progress
                }

                // 2. 用 ffprobe 提取元数据
                var title: String = url.deletingPathExtension().lastPathComponent
                var artist: String = L10n.shared.localized("import.unknown_artist")
                var album: String = L10n.shared.localized("import.unknown_album")
                var genre: String = ""
                var durationMs: UInt32 = 0
                var trackNum: UInt32 = 0

                let jsonStr = self.runCommand(ffprobe, args: [
                    "-v", "quiet",
                    "-print_format", "json",
                    "-show_format",
                    url.path
                ], timeout: 15)

                if let data = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let fmt = json["format"] as? [String: Any] {
                    if let tags = fmt["tags"] as? [String: String] {
                        title = tags["title"] ?? title
                        artist = tags["artist"] ?? artist
                        album = tags["album"] ?? album
                        genre = tags["genre"] ?? genre
                        trackNum = UInt32(tags["track"]?.components(separatedBy: "/").first ?? "0") ?? 0
                    }
                    durationMs = UInt32((fmt["duration"] as? Double ?? 0) * 1000)
                }

                // 3. 生成目标路径
                let dirIndex = Int.random(in: 0...49)
                let dirName = String(format: "F%02d", dirIndex)
                let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                let randomName = String((0..<4).map { _ in letters.randomElement()! })
                let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension.lowercased()
                let remotePath = "/iTunes_Control/Music/\(dirName)/\(randomName).\(ext)"

                // 4. 调用 afc_write 写入文件
                let output = self.runCommand(afcWrite, args: self.afcArgs([udid, url.path, remotePath]), timeout: 120)

                // 5. 检查写入结果
                if output.hasPrefix("OK:") {
                    // 获取本地文件大小
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt32) ?? 0

                    let filePath = remotePath.dropFirst().replacingOccurrences(of: "/", with: ":")
                    let track = MusicTrack(
                        id: UInt32(self.tracks.count + importedTracks.count + 1),
                        title: title,
                        artist: artist,
                        album: album,
                        genre: genre,
                        filePath: filePath,
                        trackNumber: max(1, trackNum),
                        duration: durationMs,
                        fileSize: fileSize
                    )
                    importedTracks.append(track)
                } else {
                    failedCount += 1
                    bootstrapLog("importTracks: afc_write failed for \(url.lastPathComponent): \(output)")
                }
            }

            // 6. 完成：追加到 tracks 数组
            DispatchQueue.main.async {
                if !importedTracks.isEmpty {
                    self.tracks.append(contentsOf: importedTracks)
                    self.tracks.sort { $0.artist == $1.artist ? $0.album < $1.album : $0.artist < $1.artist }
                }

                if failedCount == 0 {
                    self.busyMessage = String(format: L10n.shared.localized("import.complete"), importedTracks.count)
                } else {
                    self.busyMessage = String(format: L10n.shared.localized("import.failed"), "导入 \(importedTracks.count) 首成功，\(failedCount) 首失败")
                }
                self.busyProgress = 1.0
                self.isBusy = false
                self.isImporting = false
            }
        }
    }

    // MARK: - ===== 删除功能 =====

    func deleteTracks(_ tracksToDelete: [MusicTrack]) {
        guard !tracksToDelete.isEmpty, let device = selectedDevice else { return }

        DispatchQueue.main.async {
            self.isBusy = true
            self.busyProgress = 0
        }

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

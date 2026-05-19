import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @ObservedObject var deviceManager: DeviceManager
    @StateObject private var l10n = L10n.shared
    @State private var selectedSidebar: SidebarSelection = .allSongs
    @State private var searchText: String = ""
    @State private var selectedTrackIDs: Set<UInt32> = []
    @State private var showingSettings: Bool = false
    @State private var showingExportPicker: Bool = false
    @State private var showingDeleteConfirm: Bool = false
    @State private var pendingDeleteTracks: [MusicTrack] = []
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""

    enum SidebarSelection: Hashable {
        case allSongs
        case recentlyAdded
        case albums
        case artists
        case playlists
    }

    private var selectedTracks: [MusicTrack] {
        deviceManager.tracks.filter { selectedTrackIDs.contains($0.id) }
    }

    var body: some View {
        NavigationSplitView {
            // 左侧边栏：设备列表 + 分类
            List {
                // 设备区
                if !deviceManager.discoveredDevices.isEmpty {
                    Section(header: Text(l10n.localized("device.title"))
                        .font(.headline)) {
                        ForEach(deviceManager.discoveredDevices) { device in
                            HStack {
                                Image(systemName: deviceManager.selectedDevice?.udid == device.udid ? "ipod.fill" : "ipod")
                                    .foregroundColor(deviceManager.selectedDevice?.udid == device.udid ? .accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.body)
                                    Text("iOS \(device.iOSVersion)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if deviceManager.selectedDevice?.udid == device.udid {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // 判断该设备的连接模式
                                // 简化：重新 refresh 让 DeviceManager 自动选择模式
                                deviceManager.selectDevice(device, mode: deviceManager.activeConnectionMode)
                            }
                        }
                    }
                }

                // 音乐分类区（仅连接后显示）
                if deviceManager.isConnected {
                    Section(header: Text(l10n.localized("sidebar.category"))
                        .font(.headline)) {
                        Label(l10n.localized("sidebar.all_songs"), systemImage: "music.note.list")
                            .tag(SidebarSelection.allSongs)
                            .onTapGesture { selectedSidebar = .allSongs }

                        Label(l10n.localized("sidebar.recently_added"), systemImage: "clock")
                            .tag(SidebarSelection.recentlyAdded)
                            .onTapGesture { selectedSidebar = .recentlyAdded }

                        Label(l10n.localized("sidebar.albums"), systemImage: "square.stack")
                            .tag(SidebarSelection.albums)
                            .onTapGesture { selectedSidebar = .albums }

                        Label(l10n.localized("sidebar.artists"), systemImage: "person.2")
                            .tag(SidebarSelection.artists)
                            .onTapGesture { selectedSidebar = .artists }

                        Label(l10n.localized("sidebar.playlists"), systemImage: "list.bullet")
                            .tag(SidebarSelection.playlists)
                            .onTapGesture { selectedSidebar = .playlists }
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 200)
        } detail: {
            ZStack {
                VStack(spacing: 0) {
                    // 顶部工具栏
                    HStack {
                        Text(titleForSelection(selectedSidebar))
                            .font(.title2.bold())

                        Spacer()

                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField(l10n.localized("toolbar.search_placeholder"), text: $searchText)
                                .textFieldStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray).opacity(0.1))
                        .cornerRadius(6)
                        .frame(width: 280)

                        // 设备管理按钮（多台设备时显示）
                        if deviceManager.discoveredDevices.count > 1 {
                            Button(action: { deviceManager.showingDevicePicker = true }) {
                                Image(systemName: "ipod")
                            }
                            .help(l10n.localized("device.switch"))
                        }

                        // 导入按钮
                        Button(action: { pickFilesToImport() }) {
                            Label(l10n.localized("toolbar.import"), systemImage: "square.and.arrow.down")
                        }
                        .disabled(!deviceManager.isConnected || deviceManager.isBusy)
                        .help(l10n.localized("toolbar.import_help"))

                        Button(action: { showingExportPicker = true }) {
                            Label(l10n.localized("toolbar.export"), systemImage: "square.and.arrow.up")
                        }
                        .disabled(selectedTracks.isEmpty || !deviceManager.isConnected)
                        .help(l10n.localized("toolbar.export_help"))

                        Button(action: { showingDeleteConfirm = true }) {
                            Label(l10n.localized("toolbar.delete"), systemImage: "trash")
                        }
                        .disabled(selectedTracks.isEmpty || !deviceManager.isConnected || deviceManager.isBusy)
                        .keyboardShortcut(.delete, modifiers: [])
                        .help(l10n.localized("toolbar.delete_help", selectedTracks.count))

                        Button(action: {
                            if deviceManager.isScanning {
                                deviceManager.cancelScan()
                            } else {
                                deviceManager.refreshDevices()
                            }
                        }) {
                            Image(systemName: deviceManager.isScanning ? "xmark.circle" : "arrow.clockwise")
                        }
                        .help(deviceManager.isScanning ? l10n.localized("toolbar.cancel_scan") : l10n.localized("toolbar.refresh"))

                        Button(action: { showingSettings = true }) {
                            Image(systemName: "globe")
                        }
                        .help(l10n.localized("menu.language"))
                        .padding(.leading, 4)
                    }
                    .padding()

                    Divider()

                    // 主内容区
                    if !deviceManager.isConnected {
                        // 未连接状态
                        VStack(spacing: 16) {
                            Image(systemName: "ipod")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            Text(deviceManager.connectionStatus)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 400)
                            if !deviceManager.discoveredDevices.isEmpty {
                                Text(String(format: l10n.localized("device.found_count"), deviceManager.discoveredDevices.count))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Button(action: { deviceManager.refreshDevices() }) {
                                Label(l10n.localized("toolbar.refresh"), systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        switch selectedSidebar {
                        case .allSongs:
                            MusicListView(
                                tracks: filteredTracks,
                                selectedTrackIDs: $selectedTrackIDs,
                                onExportSingle: { track in exportSingleTrack(track) },
                                onDeleteSingle: { track in confirmDelete([track]) }
                            )

                        case .recentlyAdded:
                            MusicListView(
                                tracks: filteredTracks.sorted { $0.title < $1.title },
                                selectedTrackIDs: $selectedTrackIDs,
                                onExportSingle: { track in exportSingleTrack(track) },
                                onDeleteSingle: { track in confirmDelete([track]) }
                            )

                        case .albums:
                            AlbumView(tracks: filteredTracks)

                        case .artists:
                            ArtistView(tracks: filteredTracks)

                        case .playlists:
                            VStack {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 50))
                                    .foregroundColor(.secondary)
                                Text(l10n.localized("content.no_playlists"))
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 忙碌状态覆盖层
                if deviceManager.isBusy {
                    VStack(spacing: 12) {
                        ProgressView(value: deviceManager.busyProgress)
                            .progressViewStyle(.linear)
                        Text(deviceManager.busyMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 8)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers: providers)
                return true
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    if deviceManager.isConnected {
                        Image(systemName: deviceManager.activeConnectionMode == "wifi" ? "wifi" : "cable")
                            .foregroundColor(deviceManager.activeConnectionMode == "wifi" ? .blue : .green)
                        Label(deviceManager.selectedDevice?.name ?? "", systemImage: "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Label(l10n.localized("device.disconnected"), systemImage: "circle")
                            .foregroundColor(.secondary)
                    }
                    if !selectedTrackIDs.isEmpty {
                        Text("\(selectedTrackIDs.count)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(10)
                    }
                }
            }
        }

        // ===== Sheets & Dialogs =====
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }

        // 设备选择 Sheet
        .sheet(isPresented: $deviceManager.showingDevicePicker) {
            DevicePickerView()
                .environmentObject(deviceManager)
        }

        .sheet(isPresented: $showingExportPicker) {
            VStack {
                Text(l10n.localized("export.hint"))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
                HStack(spacing: 16) {
                    Button(l10n.localized("export.select")) {
                        pickDirectoryAndExport()
                        showingExportPicker = false
                    }
                    .keyboardShortcut(.return)
                    Button(l10n.localized("common.cancel")) {
                        showingExportPicker = false
                    }
                    .keyboardShortcut(.escape)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(width: 400, height: 180)
        }

        .alert(l10n.localized("delete.confirm_title"), isPresented: $showingDeleteConfirm) {
            Button(l10n.localized("common.cancel"), role: .cancel) {}
            Button(l10n.localized("delete.confirm_action"), role: .destructive) {
                executeDelete()
            }
        } message: {
            Text(deleteConfirmMessage())
        }

        .task {
            deviceManager.refreshDevices()
        }
        .id(l10n.effectiveLanguage)
    }

    // MARK: - 导出逻辑

    private func exportSingleTrack(_ track: MusicTrack) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = l10n.localized("export.pick_folder")
        panel.prompt = l10n.localized("export.select")

        if panel.runModal() == .OK, let url = panel.url {
            deviceManager.exportTracks([track], to: url)
        }
    }

    private func pickDirectoryAndExport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = l10n.localized("export.pick_folder")
        panel.prompt = l10n.localized("export.select")

        if panel.runModal() == .OK, let url = panel.url {
            let toExport = selectedTracks.isEmpty ? filteredTracks : Array(selectedTracks)
            deviceManager.exportTracks(toExport, to: url)
        }
    }

    // MARK: - 删除逻辑

    private func confirmDelete(_ tracksToDelete: [MusicTrack]) {
        pendingDeleteTracks = tracksToDelete
        showingDeleteConfirm = true
    }

    private func deleteConfirmMessage() -> String {
        let count = pendingDeleteTracks.count
        if count == 1, let first = pendingDeleteTracks.first {
            return String(format: l10n.localized("delete.confirm_message_single"), first.title)
        }
        return String(format: l10n.localized("delete.confirm_message_multi"), count)
    }

    private func executeDelete() {
        if pendingDeleteTracks.isEmpty {
            pendingDeleteTracks = Array(selectedTracks)
        }
        deviceManager.deleteTracks(pendingDeleteTracks)
        selectedTrackIDs.removeAll()
        pendingDeleteTracks = []
    }

    // MARK: - 辅助方法

    private func titleForSelection(_ sel: SidebarSelection) -> String {
        switch sel {
            case .allSongs: return l10n.localized("sidebar.all_songs")
            case .recentlyAdded: return l10n.localized("sidebar.recently_added")
            case .albums: return l10n.localized("sidebar.albums")
            case .artists: return l10n.localized("sidebar.artists")
            case .playlists: return l10n.localized("sidebar.playlists")
        }
    }

    private var filteredTracks: [MusicTrack] {
        if searchText.isEmpty { return deviceManager.tracks }
        let q = searchText.lowercased()
        return deviceManager.tracks.filter {
            $0.title.lowercased().contains(q) ||
            $0.artist.lowercased().contains(q) ||
            $0.album.lowercased().contains(q)
        }
    }

    // MARK: - 导入逻辑

    private func pickFilesToImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = true
        panel.title = l10n.localized("import.pick_files")
        panel.prompt = l10n.localized("toolbar.import")

        // 支持的文件类型
        panel.allowedContentTypes = [
            UTType(filenameExtension: "m4a")!,
            UTType(filenameExtension: "mp3")!,
        ]

        if panel.runModal() == .OK {
            deviceManager.importTracks(panel.urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        guard deviceManager.isConnected else { return }
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, error in
                defer { group.leave() }
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                urls.append(url)
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                deviceManager.importTracks(urls)
            }
        }
    }

}

// MARK: - 设备选择视图
struct DevicePickerView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 16) {
            Text(l10n.localized("device.picker_title"))
                .font(.title2.bold())

            Text(l10n.localized("device.picker_hint"))
                .font(.caption)
                .foregroundColor(.secondary)

            List(deviceManager.discoveredDevices) { device in
                HStack {
                    Image(systemName: "ipod")
                    VStack(alignment: .leading) {
                        Text(device.name)
                            .font(.body)
                        Text("iOS \(device.iOSVersion) · \(device.productType)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if deviceManager.selectedDevice?.udid == device.udid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    deviceManager.selectDevice(device)
                    dismiss()
                }
            }
            .listStyle(PlainListStyle())
            .frame(height: min(CGFloat(deviceManager.discoveredDevices.count) * 60 + 20, 300))

            HStack {
                Button(l10n.localized("common.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button(l10n.localized("toolbar.refresh")) {
                    deviceManager.refreshDevices()
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

// MARK: - 关于对话框
struct AboutView: View {
    @StateObject private var l10n = L10n.shared
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("JayTune")
                .font(.title.bold())

            Text(l10n.localized("about.description"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)

            Divider()

            HStack {
                Text(l10n.localized("about.version"))
                    .foregroundColor(.secondary)
                Spacer()
                Text(appVersion)
                    .foregroundColor(.primary)
            }

            HStack {
                Text(l10n.localized("settings.connection"))
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: DeviceManager.shared.activeConnectionMode == "wifi" ? "wifi" : "cable")
                        .foregroundColor(DeviceManager.shared.activeConnectionMode == "wifi" ? .blue : .green)
                    Text(DeviceManager.shared.activeConnectionMode == "wifi" ?
                         l10n.localized("settings.wifi_mode") :
                         "USB")
                }
            }

            Spacer()

            Button(l10n.localized("common.back")) { dismiss() }
                .keyboardShortcut(.escape)
        }
        .frame(width: 420, height: 400)
        .padding(28)
    }
}

// MARK: - 设置面板（语言 + 连接）
struct SettingsView: View {
    @StateObject private var l10n = L10n.shared
    @ObservedObject var deviceManager = DeviceManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(l10n.localized("settings.title"))
                .font(.title.bold())

            Divider()

            // 语言选择
            VStack(alignment: .leading, spacing: 12) {
                Text(l10n.localized("settings.language"))
                    .font(.headline)

                ForEach(AppLanguage.allCases) { lang in
                    Button(action: { l10n.switchLanguage(to: lang) }) {
                        HStack {
                            Text(lang.flag).font(.title2)
                            Text(lang.displayName)
                            Spacer()
                            if l10n.currentLanguage == lang {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                            } else {
                                Image(systemName: "circle").foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(l10n.currentLanguage == lang ? Color.accentColor.opacity(0.1) : Color.clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)

            // 连接模式
            VStack(alignment: .leading, spacing: 12) {
                Text(l10n.localized("settings.connection"))
                    .font(.headline)

                Toggle(isOn: $deviceManager.useWiFi) {
                    HStack {
                        Image(systemName: "wifi")
                            .foregroundColor(.accentColor)
                        Text(l10n.localized("settings.wifi_mode"))
                    }
                }

                Text(l10n.localized("settings.wifi_hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)

            Text(l10n.localized("settings.restart_hint"))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            HStack {
                Spacer()
                Button(l10n.localized("common.back")) { dismiss() }
                    .keyboardShortcut(.escape)
            }
        }
        .frame(width: 420, height: 520)
        .padding(24)
    }
}

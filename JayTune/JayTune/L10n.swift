import Foundation
import SwiftUI

// MARK: - 支持的语言
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"    // 跟随系统
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System / 系统"
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }

    var flag: String {
        switch self {
        case .system: return "🌐"
        case .chinese: return "🇨🇳"
        case .english: return "🇺🇸"
        }
    }
}

// MARK: - 本地化管理器
final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var currentLanguage: AppLanguage {
        didSet { saveLanguagePreference() }
    }

    @Published var effectiveLanguage: String  // 实际生效的语言代码 ("en" 或 "zh-Hans")

    private var stringTable: [String: String] = [:]
    private let defaultsKey = "jaytune_language"

    private init() {
        // 读取用户偏好
        let savedRaw = UserDefaults.standard.string(forKey: defaultsKey)
        let saved = savedRaw.flatMap { AppLanguage(rawValue: $0) } ?? .system
        self.currentLanguage = saved

        // 计算实际语言
        let resolved = Self.resolveLanguage(saved)
        self.effectiveLanguage = resolved

        // 加载字符串表
        loadStringTable(for: resolved)

        // 监听系统语言变化（通过 NSCurrentLocaleDidChangeNotification）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemLocaleChanged),
            name: NSLocale.currentLocaleDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 解析实际语言
    static func resolveLanguage(_ preference: AppLanguage) -> String {
        switch preference {
        case .system:
            let langs = Locale.preferredLanguages
            let langCode = langs.first ?? "en"

            // 中文系语言 → zh-Hans，其他 → en
            if langCode.hasPrefix("zh") || langCode.hasPrefix("Hans") {
                return "zh-Hans"
            } else if ["ja", "ko", "vi", "th"].contains(langCode.prefix(2)) {
                // CJK 系列默认用中文（更接近）
                return "zh-Hans"
            }
            return "en"
        case .chinese:
            return "zh-Hans"
        case .english:
            return "en"
        }
    }

    // MARK: - 加载字符串表
    private func loadStringTable(for lang: String) {
        // 防御：Bundle.main 可能尚未正确设置，先尝试取 URL
        let bundle = Bundle.main
        let url = bundle.url(forResource: "Localizable", withExtension: "strings",
                             subdirectory: "\(lang).lproj")
              ?? bundle.url(forResource: "Localizable", withExtension: "strings")
        guard let url = url else {
            loadFallbackTable(lang: lang)
            return
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            parseStringsContent(content)
        } catch {
            loadFallbackTable(lang: lang)
        }
    }

    /// 内嵌 fallback 字符串表（当 .strings 文件缺失时使用）
    private func loadFallbackTable(lang: String) {
        if lang == "zh-Hans" {
            stringTable = Self.zhFallback
        } else {
            stringTable = Self.enFallback
        }
    }

    /// 解析标准 .strings 文件格式
    private func parseStringsContent(_ content: String) {
        var table: [String: String] = [:]

        // 匹配 "key" = "value"; 格式
        let pattern = #""(.+?)"\s*=\s*"(.+?)";"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let nsStr = content as NSString
        regex.enumerateMatches(in: content, range: NSRange(location: 0, length: nsStr.length)) { match, _, _ in
            guard let match = match else { return }
            let keyRange = match.range(at: 1)
            let valueRange = match.range(at: 2)
            guard keyRange.location != NSNotFound && valueRange.location != NSNotFound else { return }
            let key = nsStr.substring(with: keyRange)
            let value = nsStr.substring(with: valueRange)
            table[key] = value
        }

        stringTable = table
    }

    // MARK: - 核心本地化方法
    /// 获取本地化字符串
    func localized(_ key: String, _ args: CVarArg...) -> String {
        let template = stringTable[key] ?? key
        if args.isEmpty { return template }
        return String(format: template, arguments: args)
    }

    /// 带默认值的本地化
    func localized(_ key: String, fallback: String) -> String {
        stringTable[key] ?? fallback
    }

    // MARK: - 切换语言
    func switchLanguage(to newLang: AppLanguage) {
        currentLanguage = newLang
        let resolved = Self.resolveLanguage(newLang)
        effectiveLanguage = resolved
        loadStringTable(for: resolved)
    }

    /// 刷新当前语言设置（当系统语言变化时调用）
    @objc private func systemLocaleChanged() {
        if currentLanguage == .system {
            let resolved = Self.resolveLanguage(.system)
            effectiveLanguage = resolved
            loadStringTable(for: resolved)
        }
    }

    private func saveLanguagePreference() {
        UserDefaults.standard.set(currentLanguage.rawValue, forKey: defaultsKey)
    }

    // MARK: - 是否为中文环境
    var isChinese: Bool {
        effectiveLanguage.hasPrefix("zh")
    }

    // MARK: - Fallback 字符串表（编译进二进制，确保永远可用）
    static let zhFallback: [String: String] = [
        // === 侧边栏 ===
        "sidebar.all_songs":          "全部歌曲",
        "sidebar.recently_added":     "最近添加",
        "sidebar.albums":             "专辑",
        "sidebar.artists":            "艺术家",
        "sidebar.playlists":          "播放列表",
        "sidebar.category":           "分类",

        // === 设备状态 ===
        "device.connected":           "已连接",
        "device.disconnected":        "未连接",
        "device.not_connected":       "设备未连接",
        "device.detecting":           "正在检测设备...",
        "device.not_found":           "未找到设备，请连接 iPod touch 或开启 WiFi 同步",
        "device.not_found_detail":    "未找到 iPod touch，请确认已连接并信任此电脑",
        "device.not_found_wifi_hint": "未找到设备 — 请确认：\n  • iPod touch 与电脑在同一 WiFi\n  • 已在 iTunes/Finder 中开启「通过 Wi-Fi 同步」\n  • 或使用 USB 线连接",
        "device.no_music":           "未找到音乐文件",
        "device.title":              "设备",
        "device.switch":            "切换设备",
        "device.picker_title":       "选择设备",
        "device.picker_hint":        "请选择要管理的 iPod 设备",
        "device.found_count":        "发现 %d 台设备",
        "device.multiple_found":     "发现 %d 台设备，请选择",
        "device.scanning":           "正在扫描音乐库（%d 个目录）…",
        "device.scan_progress":      "已扫描 %d/%d 个目录，%d 首歌曲",
        "device.scan_complete":      "%@ · %d 首歌曲",

        // === 工具栏 ===
        "toolbar.search_placeholder": "搜索歌曲、艺术家、专辑...",
        "toolbar.import":            "导入",
        "toolbar.import_failed":     "导入失败",
        "toolbar.refresh":           "刷新设备",
        "toolbar.cancel_scan":       "取消扫描",

        // === 内容区 ===
        "content.no_playlists":      "暂无播放列表",
        "album.track_count":         "%d 首",
        "album.back_to_list":        "返回专辑列表",
        "artist.back_to_list":       "返回艺术家列表",
        "common.back":               "返回",

        // === 导入 ===
        "import.unknown_artist":     "未知艺术家",
        "import.unknown_album":      "未知专辑",
        "toolbar.import_help":       "导入音乐文件到设备",
        "import.pick_files":        "选择要导入的音乐文件",
        "import.progress":          "正在导入：%@",
        "import.complete":          "✅ 已导入 %d 首歌曲",
        "import.failed":            "❌ 导入失败：%@",
        "import.batch_progress":    "导入中 (%d/%d)：%@…",
        "import.no_device":         "请先连接设备再导入",
        "import.unsupported_format": "不支持的文件格式，仅支持 .m4a 和 .mp3",
        "import.drag_hint":         "拖放音乐文件到此处导入",

        // === 应用名 ===
        "app.name":                  "JayTune",
        "app.menu.about":            "关于 JayTune",
        "app.menu.preferences":      "偏好设置…",
        "app.menu.quit":             "退出 JayTune",

        // === 文件菜单 ===
        "menu.file":                 "文件",
        "menu.import_media":         "导入媒体文件…",
        "menu.close_window":         "关闭窗口",

        // === 编辑菜单 ===
        "menu.edit":                 "编辑",
        "menu.undo":                 "撤销",
        "menu.redo":                 "重做",
        "menu.cut":                  "剪切",
        "menu.copy":                 "复制",
        "menu.paste":                "粘贴",
        "menu.select_all":           "全选",

        // === 显示菜单 ===
        "menu.view":                 "显示",
        "menu.toolbar":              "工具栏",
        "menu.sidebar":              "侧边栏",

        // === 帮助菜单 ===
        "menu.help":                 "帮助",
        "menu.website":              "JayTune 网站",
        "menu.language":             "语言 / Language",

        // === 设置面板 ===
        "settings.title":            "偏好设置",
        "settings.language":         "语言",
        "settings.auto_detect":      "跟随系统",
        "settings.restart_hint":     "部分界面需要重启应用后生效",
        "settings.connection":       "连接",
        "settings.wifi_mode":        "WiFi 无线连接模式",
        "settings.wifi_hint":        "WiFi 模式无需 USB 线缆，但速度较慢。设备需与电脑在同一 WiFi 网络。",

        // === 关于 ===
        "about.title":               "关于 JayTune",
        "about.version":             "版本",
        "about.description":         "iPod touch 音乐管理工具\n通过 AFC 协议读取和管理音乐库",

        // === 导出 ===
        "toolbar.export":            "导出",
        "toolbar.export_help":       "导出选中歌曲到电脑",
        "export.pick_folder":        "选择导出目录",
        "export.select":             "导出",
        "export.hint":               "选择一个文件夹来保存导出的歌曲",
        "export.progress":           "正在导出：%@",
        "export.complete":           "✅ 导出完成：%@",
        "export.failed":            "❌ 导出失败：%@",
        "export.batch_progress":     "导出中 (%d/%d)：%@…",
        "export.batch_complete":     "✅ 已导出 %d 首歌曲",

        // === 删除 ===
        "toolbar.delete":            "删除",
        "toolbar.delete_help":       "删除 %d 首选中的歌曲",
        "delete.confirm_title":      "确认删除",
        "delete.confirm_action":     "删除",
        "delete.confirm_message_single": "确定要删除「%@」吗？此操作不可撤销。",
        "delete.confirm_message_multi": "确定要删除这 %d 首歌曲吗？此操作不可撤销。",
        "common.cancel":             "取消",
        "delete.progress":           "删除中 (%d/%d)：%@…",
        "delete.complete":            "已删除 %d 首歌曲",

        // === 右键菜单 ===
        "context.export":            "导出歌曲",
        "context.delete":            "删除歌曲",
        "context.copy_info":         "复制曲目信息",
    ]

    static let enFallback: [String: String] = [
        // === Sidebar ===
        "sidebar.all_songs":          "All Songs",
        "sidebar.recently_added":     "Recently Added",
        "sidebar.albums":             "Albums",
        "sidebar.artists":            "Artists",
        "sidebar.playlists":          "Playlists",
        "sidebar.category":           "Library",

        // === Device Status ===
        "device.connected":           "Connected",
        "device.disconnected":        "Disconnected",
        "device.not_connected":       "No Device",
        "device.detecting":           "Detecting device...",
        "device.not_found":           "No device found, connect iPod touch or enable WiFi sync",
        "device.not_found_detail":    "iPod touch not found. Please connect and trust this computer.",
        "device.not_found_wifi_hint": "No device found — please check:\n  • iPod touch is on the same WiFi network\n  • Wi-Fi sync is enabled in iTunes/Finder settings\n  • Or connect via USB cable",
        "device.no_music":           "No music files found",
        "device.title":              "Devices",
        "device.switch":            "Switch Device",
        "device.picker_title":       "Select Device",
        "device.picker_hint":        "Select the iPod to manage",
        "device.found_count":        "Found %d device(s)",
        "device.multiple_found":     "Found %d devices, please select",
        "device.scanning":           "Scanning music library (%d directories)…",
        "device.scan_progress":      "Scanned %d/%d directories, %d tracks",
        "device.scan_complete":      "%@ · %d tracks",

        // === Toolbar ===
        "toolbar.search_placeholder": "Search songs, artists, albums...",
        "toolbar.import":            "Import",
        "toolbar.import_failed":     "Import failed",
        "toolbar.refresh":           "Refresh Device",
        "toolbar.cancel_scan":       "Cancel Scan",

        // === Content ===
        "content.no_playlists":      "No Playlists",
        "album.track_count":         "%d tracks",
        "album.back_to_list":        "Back to Albums",
        "artist.back_to_list":       "Back to Artists",
        "common.back":               "Back",

        // === Import ===
        "import.unknown_artist":     "Unknown Artist",
        "import.unknown_album":      "Unknown Album",
        "toolbar.import_help":       "Import music files to device",
        "import.pick_files":        "Select music files to import",
        "import.progress":          "Importing: %@",
        "import.complete":          "✅ Imported %d tracks",
        "import.failed":            "❌ Import failed: %@",
        "import.batch_progress":    "Importing (%d/%d): %@…",
        "import.no_device":         "Please connect a device first",
        "import.unsupported_format": "Unsupported format, only .m4a and .mp3 are supported",
        "import.drag_hint":         "Drop music files here to import",

        // === App Name ===
        "app.name":                  "JayTune",
        "app.menu.about":            "About JayTune",
        "app.menu.preferences":      "Preferences…",
        "app.menu.quit":             "Quit JayTune",

        // === File Menu ===
        "menu.file":                 "File",
        "menu.import_media":         "Import Media…",
        "menu.close_window":         "Close Window",

        // === Edit Menu ===
        "menu.edit":                 "Edit",
        "menu.undo":                 "Undo",
        "menu.redo":                 "Redo",
        "menu.cut":                  "Cut",
        "menu.copy":                 "Copy",
        "menu.paste":                "Paste",
        "menu.select_all":           "Select All",

        // === View Menu ===
        "menu.view":                 "View",
        "menu.toolbar":              "Toolbar",
        "menu.sidebar":              "Sidebar",

        // === Help Menu ===
        "menu.help":                 "Help",
        "menu.website":              "JayTune Website",
        "menu.language":             "Language",

        // === Settings ===
        "settings.title":            "Preferences",
        "settings.language":         "Language",
        "settings.auto_detect":      "System Default",
        "settings.restart_hint":     "Some UI elements require restart to take effect",
        "settings.connection":       "Connection",
        "settings.wifi_mode":        "WiFi Wireless Mode",
        "settings.wifi_hint":        "WiFi mode works without USB cable but is slower. Device must be on the same WiFi network.",

        // === About ===
        "about.title":               "About JayTune",
        "about.version":             "Version",
        "about.description":         "iPod touch Music Manager\nManage music library via AFC protocol",

        // === Export ===
        "toolbar.export":            "Export",
        "toolbar.export_help":       "Export selected tracks to computer",
        "export.pick_folder":        "Choose Export Folder",
        "export.select":             "Export",
        "export.hint":               "Select a folder for exported songs",
        "export.progress":           "Exporting: %@",
        "export.complete":           "✅ Export complete: %@",
        "export.failed":            "❌ Export failed: %@",
        "export.batch_progress":     "Exporting (%d/%d): %@…",
        "export.batch_complete":     "✅ Exported %d tracks",

        // === Delete ===
        "toolbar.delete":            "Delete",
        "toolbar.delete_help":       "Delete %d selected track(s)",
        "delete.confirm_title":      "Confirm Delete",
        "delete.confirm_action":     "Delete",
        "delete.confirm_message_single": "Are you sure you want to delete \"%@\"? This cannot be undone.",
        "delete.confirm_message_multi": "Are you sure you want to delete these %d songs? This cannot be undone.",
        "common.cancel":             "Cancel",
        "delete.progress":           "Deleting (%d/%d): %@…",
        "delete.complete":           "Deleted %d track(s)",

        // === Context Menu ===
        "context.export":            "Export Song",
        "context.delete":            "Delete Song",
        "context.copy_info":         "Copy Track Info",
    ]
}

// MARK: - SwiftUI便捷扩展
extension Text {
    /// 创建本地化文本
    static func l10n(_ key: String, _ args: CVarArg...) -> Text {
        Text(L10n.shared.localized(key, args))
    }
}

// MARK: - LocalizedStringKey 扩展（用于 Label 等）
extension String {
    /// 获取本地化值
    var localized: String {
        L10n.shared.localized(self)
    }
}

import SwiftUI

@main
struct JayTuneApp: App {
    @StateObject private var deviceManager = DeviceManager.shared
    @StateObject private var l10n = L10n.shared

    var body: some Scene {
        WindowGroup {
            ContentView(deviceManager: deviceManager)
                .environmentObject(deviceManager)
                .environmentObject(l10n)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 700)
        // ===== 本地化菜单栏 =====
        .commands {
            // 应用菜单（Preferences）
            CommandGroup(after: .appInfo) {
                Button(l10n.localized("app.menu.preferences")) {
                    NotificationCenter.default.post(name: .jayTuneShowSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // 文件菜单
            CommandGroup(replacing: .newItem) {
                Button(l10n.localized("menu.import_media")) {
                    NotificationCenter.default.post(name: .jayTuneImportMedia, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            // 帮助菜单 — 语言切换入口 + 关于
            CommandGroup(after: .help) {
                Divider()
                Button(l10n.localized("menu.language")) {
                    NotificationCenter.default.post(name: .jayTuneShowSettings, object: nil)
                }
                Divider()
                Button(l10n.localized("app.menu.about")) {
                    NSApp.sendAction(#selector(NSApplication.orderFrontStandardAboutPanel(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
            }

            // 自定义视图菜单
            CommandMenu(l10n.localized("menu.view")) {
                Toggle(l10n.localized("menu.toolbar"), isOn: .constant(true))
                    .keyboardShortcut("t", modifiers: .command)
                Toggle(l10n.localized("menu.sidebar"), isOn: .constant(true))
                    .keyboardShortcut("s", modifiers: .command)
            }

            // 语言快速切换子菜单
            CommandMenu(l10n.localized("menu.language")) {
                Button("🌐 \(l10n.localized("settings.auto_detect"))") {
                    l10n.switchLanguage(to: .system)
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])
                Button("🇨🇳 简体中文") { l10n.switchLanguage(to: .chinese) }
                    .keyboardShortcut("2", modifiers: [.command, .shift])
                Button("🇺🇸 English") { l10n.switchLanguage(to: .english) }
                    .keyboardShortcut("3", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - 通知扩展
extension Notification.Name {
    static let jayTuneImportMedia = Notification.Name("jayTuneImportMedia")
    static let jayTuneShowSettings = Notification.Name("jayTuneShowSettings")
}

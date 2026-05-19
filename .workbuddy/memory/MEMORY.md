# JayTune 项目记忆

## 项目概述
JayTune — macOS SwiftUI 应用，面向 iPod 设备的音乐管理工具。通过 AFC 协议（libimobiledevice）读取/管理 iPod 音乐库。

## 技术栈
- **语言**: Swift 5.9+, SwiftUI, AppKit
- **构建**: `./build.sh`（xcrun swiftc CLI 编译，非 Xcode 项目）
- **目标**: macOS 14.0+ (arm64)
- **依赖**: libimobiledevice (afc_ls/afc_read2/afc_rm/afc_head/afc_write), ffprobe (可选)
- **仓库**: GitHub 私有仓库 mrcuo/JayTune

## 项目结构
```
JayTune/
├── JayTune/JayTune/         # Swift 源码
│   ├── JayTuneApp.swift     # App 入口
│   ├── ContentView.swift    # 主 UI + 设备选择/设置/关于/导出/删除
│   ├── DeviceManager.swift  # iPod 通信核心（USB/WiFi 双模式）
│   ├── L10n.swift           # 国际化管理器（中/英 + fallback）
│   ├── Models/MusicTrack.swift  # 曲目数据模型
│   └── Views/               # MusicListView/AlbumView/ArtistView
├── JayTune/Tools/           # AFC C 工具（afc_ls.c/afc_read2.c/afc_rm.c/afc_head.c/afc_write.c）
├── JayTune/en.lproj/        # 英文本地化
├── JayTune/zh-Hans.lproj/   # 中文本地化
├── JayTune/IconSet.iconset/  # 图标源文件
├── build.sh                 # 构建脚本
└── Package.swift            # SPM 配置
```

## 已完成功能
- Phase 1-3: 设备检测、音乐库扫描、歌曲/专辑/艺术家视图
- Phase 4: 国际化 i18n（L10n 单例 + fallback 字符串表 + 菜单栏快捷键）
- Phase 5: 音乐导出/删除（单首+批量，进度覆盖层，右键菜单）
- Phase 6: WiFi 同步模式 + UI 打磨（设置面板、关于对话框、连接模式指示器）
- 修复: 闪退（init 不再调用 refreshDevices）、图标丢失（iconutil 重新生成）、重复 App 副本
- BugFix: EXC_BAD_ACCESS 0x43 崩溃（L10n %@→%d 格式串修复，线程安全，force unwrap）
- BugFix: WiFi 连接实际由闪退导致（app 崩在前无法完成 WiFi 发现）
- 改进: 移除无用的 Import 按钮，消除 loadMusicLibrary 重复调用，添加扫描取消功能
- BugFix: 歌曲列表不完整（只显示10首/实际73首）→ 根因：WiFi下 afc_read2 传整个文件会卡死，多进程争抢AFC连接
- BugFix: 3首歌曲显示"未知"（CORW/JGKN/PNCN）→ 根因：moov atom在64KB~128KB区间，afc_head -b 65536读不完整 → 改为 -b 131072
- Phase 7: 音乐导入功能（NSOpenPanel批量选择 + 拖拽导入，afc_write写入iPod）

## 已修复的关键 Bug
- **格式串崩溃**: L10n.localized() 中 %@ 接收 Int 值 → 0x43 EXC_BAD_ACCESS。修复为 %d
- **线程安全**: @Published 属性在后台线程写入 → 包裹 DispatchQueue.main.async
- **Force unwrap**: dirs.firstIndex(of:)! → enumerated() 安全索引
- **临时文件泄漏**: 添加 cleanupTempFiles() 在扫描前清理 /tmp/jaytune_*
- **WiFi扫描卡死**: afc_read2 读整个文件在WiFi下会阻塞卡死 → 新增 afc_head 工具只读64KB头部，扫描速度提升10倍
- **3首"未知"歌曲**: CORW(以父之名)/JGKN(三年二班)/PNCN(双刀) 的 moov atom 在64KB~128KB → afc_head 改为 -b 131072（128KB）
- **AFC进程互斥**: WiFi下多个afc_read2同时运行会互相卡死 → 添加 killStaleAfcProcesses() 和 isScanRunning 互斥锁
- **runCommand超时**: 添加 timeout 参数，WiFi下15秒超时自动 terminate 子进程

## 已知问题
- Playlist 视图显示 "暂无播放列表"（未实现）
- 未签名应用需右键打开
- WiFi扫描仍有少数超时风险（15秒超时保护会跳过该曲目）

## WiFi 连接说明
- iPod touch WiFi 同步前提：iTunes/Finder 中开启「通过 Wi-Fi 同步」，与 Mac 同一网络
- idevice_id -n -l 可发现设备（显示 "(Network)" 后缀）
- AFC 工具支持 -n 参数（IDEVICE_LOOKUP_NETWORK），已验证 WiFi 读取正常
- WiFi下AFC连接**不支持多进程并发**，同一时间只能有一个afc客户端连接
- 扫描阶段用 afc_head 只读128KB头部，导出阶段用 afc_read2 传完整文件
- 当前设备 UDID: 3b566645735138d6c09b45d0d04af0f38c8c5dff（73首周杰伦歌曲）

## Roadmap（未完成）
- [ ] 播放列表管理
- [ ] 音乐播放（预览曲目）
- [ ] 批量元数据编辑
- [ ] 智能播放列表创建
- [ ] iPod 备份与恢复
- [ ] 同时支持多台 iPod

## 导入功能技术细节
- **afc_write.c**: AFC写入工具，使用 AFC_FOPEN_WRONLY + 256KB分块写入，自动创建父目录
- **NSOpenPanel**: 支持 m4a/mp3 文件类型，多选，可选文件夹
- **拖拽**: .onDrop(of: [.fileURL]) + NSItemProvider，递归遍历文件夹
- **导入流程**: 递归遍历 → 过滤 .m4a/.mp3 → ffprobe读元数据 → F00-F49随机目录 + 4字符随机文件名 → afc_write写入 → 追加到tracks数组
- **i18n**: 9个新增键（toolbar.import_help, import.pick_files, import.progress, import.complete, import.failed, import.batch_progress, import.no_device, import.unsupported_format, import.drag_hint）

## 构建命令
```bash
./build.sh          # 编译 + 打包 JayTune.app
./build.sh run      # 编译 + 启动
./build.sh clean    # 清理
```

## 构建输出
- 工作区: `/Users/zhangyajie/WorkBuddy/JayTune/JayTune.app`
- 桌面部署: `~/Desktop/JayTune.app`
- 旧工作区 `2026-05-06-task-1/` 已于 2026-05-17 清理删除

## 用户偏好
- 偏好 swiftc CLI 命令行编译，不用 Xcode 项目
- 强调 iPod 触控转盘为唯一主元素
- 先看视觉预览再整合
- 中文为主，结构化输出

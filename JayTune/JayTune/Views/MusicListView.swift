import SwiftUI

// MARK: - 音乐列表视图
struct MusicListView: View {
    let tracks: [MusicTrack]
    @Binding var selectedTrackIDs: Set<UInt32>
    var onExportSingle: ((MusicTrack) -> Void)? = nil
    var onDeleteSingle: ((MusicTrack) -> Void)? = nil

    var body: some View {
        List(tracks, selection: $selectedTrackIDs) { track in
            trackRow(for: track)
        }
        .listStyle(.inset)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - 单行（拆分为独立方法避免编译器类型推断超时）
    private func trackRow(for track: MusicTrack) -> some View {
        HStack {
            Text(rowIndex(for: track))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)

            VStack(alignment: .leading) {
                Text(track.title).font(.body)
                Text(track.artist).font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            Text(track.album)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .trailing)

            Text(formatDuration(track.duration))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)

            Text(formatFileSize(track.fileSize))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .contextMenu { contextMenuContent(for: track) }
    }

    // MARK: - 右键菜单内容
    @ViewBuilder
    private func contextMenuContent(for track: MusicTrack) -> some View {
        if let onExport = onExportSingle {
            Button(action: { onExport(track) }) {
                Label(L10n.shared.localized("context.export"), systemImage: "square.and.arrow.up")
            }
        }
        if let onDelete = onDeleteSingle {
            Button(role: .destructive, action: { onDelete(track) }) {
                Label(L10n.shared.localized("context.delete"), systemImage: "trash")
            }
        }
        Divider()
        Button(action: copyTrackInfo(track)) {
            Label(L10n.shared.localized("context.copy_info"), systemImage: "doc.on.doc")
        }
    }

    // MARK: - 辅助方法

    private func rowIndex(for track: MusicTrack) -> String {
        guard let idx = tracks.firstIndex(where: { $0.id == track.id }) else { return "?" }
        return String(idx + 1)
    }

    private func formatDuration(_ ms: UInt32) -> String {
        let seconds = Int(ms) / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func formatFileSize(_ bytes: UInt32) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
    }

    private func copyTrackInfo(_ track: MusicTrack) -> () -> Void {
        return {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString("\(track.artist) - \(track.title)", forType: .string)
        }
    }
}

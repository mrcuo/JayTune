import SwiftUI

// MARK: - 专辑视图（按专辑分组）
struct AlbumView: View {
    let tracks: [MusicTrack]
    @State private var selectedAlbum: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            if selectedAlbum == nil {
                // 显示专辑列表
                List(albums, id: \.self) { album in
                    Button(action: { selectedAlbum = album }) {
                        HStack {
                            Image(systemName: "square.stack")
                                .foregroundColor(.accentColor)
                            Text(album)
                                .font(.body)
                            Spacer()
                            Text(L10n.shared.localized("album.track_count", tracksForAlbum(album).count))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            } else {
                // 显示选中专辑的歌曲
                VStack {
                    HStack {
                        Button(action: { selectedAlbum = nil }) {
                            Label(L10n.shared.localized("album.back_to_list"), systemImage: "chevron.left")
                        }
                        .help(L10n.shared.localized("common.back"))

                        Spacer()

                        Text(selectedAlbum!)
                            .font(.headline)
                        Spacer()
                    }
                    .padding()

                    MusicListView(
                        tracks: tracksForAlbum(selectedAlbum!),
                        selectedTrackIDs: .constant([])
                    )
                }
            }
        }
    }

    private var albums: [String] {
        let albumSet = Set(tracks.map { $0.album })
        return albumSet.sorted()
    }

    private func tracksForAlbum(_ album: String) -> [MusicTrack] {
        tracks.filter { $0.album == album }
            .sorted { $0.trackNumber < $1.trackNumber }
    }
}

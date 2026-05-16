import SwiftUI

// MARK: - 艺术家视图（按艺术家分组）
struct ArtistView: View {
    let tracks: [MusicTrack]
    @State private var selectedArtist: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            if selectedArtist == nil {
                // 显示艺术家列表
                List(artists, id: \.self) { artist in
                    Button(action: { selectedArtist = artist }) {
                        HStack {
                            Image(systemName: "person.circle")
                                .foregroundColor(.accentColor)
                            Text(artist)
                                .font(.body)
                            Spacer()
                            Text("\(L10n.shared.localized("album.track_count", tracksForArtist(artist).count))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            } else {
                // 显示选中艺术家的歌曲
                VStack {
                    HStack {
                        Button(action: { selectedArtist = nil }) {
                            Label(L10n.shared.localized("artist.back_to_list"), systemImage: "chevron.left")
                        }
                        .help(L10n.shared.localized("common.back"))

                        Spacer()

                        Text(selectedArtist!)
                            .font(.headline)
                        Spacer()
                    }
                    .padding()

                    MusicListView(
                        tracks: tracksForArtist(selectedArtist!),
                        selectedTrackIDs: .constant([])
                    )
                }
            }
        }
    }

    private var artists: [String] {
        let artistSet = Set(tracks.map { $0.artist })
        return artistSet.sorted()
    }

    private func tracksForArtist(_ artist: String) -> [MusicTrack] {
        tracks.filter { $0.artist == artist }
            .sorted { $0.album < $1.album }
    }
}

import Foundation

// MARK: - MusicTrack 曲目模型
struct MusicTrack: Identifiable, Hashable {
    let id: UInt32
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var genre: String = ""
    var composer: String = ""
    var comment: String = ""
    var grouping: String = ""

    var filePath: String = ""      // MHOD type=2
    var fileType: UInt32 = 0     // 0x4d503320=MP3, 0x41414320=AAC

    var trackNumber: UInt32 = 0
    var totalTracks: UInt32 = 0
    var discNumber: UInt32 = 0
    var totalDiscs: UInt32 = 0
    var year: UInt32 = 0
    var bitrate: UInt32 = 0
    var duration: UInt32 = 0     // 毫秒
    var fileSize: UInt32 = 0     // 字节
    var rating: UInt8 = 0
    var playCount: UInt32 = 0
    var dateAdded: UInt32 = 0
    var lastPlayed: UInt32 = 0
    var compilation: Bool = false
    var dbid: UInt64 = 0

    var devicePath: String {
        "/" + filePath.replacingOccurrences(of: ":", with: "/")
    }

    /// 导出时使用的文件名（艺术家 - 曲目.扩展名）
    var exportFilename: String {
        let ext = (filePath as NSString).pathExtension.isEmpty ? "m4a" : (filePath as NSString).pathExtension
        let safeTitle = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let safeArtist = artist.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(safeArtist) - \(safeTitle).\(ext)"
    }

    // Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    static func == (lhs: MusicTrack, rhs: MusicTrack) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 模拟数据
extension MusicTrack {
    static var mockData: [MusicTrack] {
        [
            MusicTrack(id: 1, title: "Shape of You", artist: "Ed Sheeran", album: "÷ (Deluxe)", trackNumber: 1, duration: 233000, fileSize: 5600000),
            MusicTrack(id: 2, title: "Blinding Lights", artist: "The Weeknd", album: "After Hours", trackNumber: 1, duration: 200000, fileSize: 4800000),
            MusicTrack(id: 3, title: "Dynamite", artist: "BTS", album: "Dynamite (Single)", trackNumber: 1, duration: 199000, fileSize: 4700000),
            MusicTrack(id: 4, title: "Levitating", artist: "Dua Lipa", album: "Future Nostalgia", trackNumber: 3, duration: 203000, fileSize: 4900000),
            MusicTrack(id: 5, title: "Stay", artist: "The Kid LAROI, Justin Bieber", album: "F*CK LOVE 3", trackNumber: 1, duration: 141000, fileSize: 3400000),
        ]
    }
}

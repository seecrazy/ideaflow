import Foundation
import UIKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// 媒体落盘(DESIGN §10.2/§12):图片压缩 2048/0.8、缩略 400/0.7、音频 AAC 64k 单声道。
struct MediaStore {
    struct SavedImage {
        let relativePath: String
        let thumbRelativePath: String
        let fileSize: Int64
    }

    let files: AttachmentFiles

    init(files: AttachmentFiles = AttachmentFiles()) {
        self.files = files
    }

    // MARK: - 图片

    func saveImage(_ data: Data, ideaID: UUID) throws -> SavedImage {
        let dir = try files.ensureDirectory(for: ideaID)
        let name = UUID().uuidString
        let fullURL = dir.appendingPathComponent("\(name).jpg")
        let thumbURL = dir.appendingPathComponent("\(name)_thumb.jpg")

        let fullData = Self.jpegData(from: data, maxPixel: 2048, quality: 0.8)
        let thumbData = Self.jpegData(from: data, maxPixel: 400, quality: 0.7)
        try fullData.write(to: fullURL, options: .atomic)
        try thumbData.write(to: thumbURL, options: .atomic)

        let relName = "\(ideaID.uuidString)/\(name)"
        return SavedImage(relativePath: "\(relName).jpg",
                          thumbRelativePath: "\(relName)_thumb.jpg",
                          fileSize: Int64(fullData.count))
    }

    /// 下采样压缩:CGImageSource 缩略解码,避免整图解进内存(DESIGN §12.4)
    static func jpegData(from data: Data, maxPixel: CGFloat, quality: CGFloat) -> Data {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary),
              let ui = UIImage(cgImage: cg).jpegData(compressionQuality: quality) else {
            return data   // 无法解码时原样保留,宁大勿丢
        }
        return ui
    }

    // MARK: - 音频

    static let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
    ]

    /// 把录音临时文件挪入附件目录
    func saveAudio(at tempURL: URL, ideaID: UUID) throws -> (relativePath: String, fileSize: Int64, duration: Double?) {
        let dir = try files.ensureDirectory(for: ideaID)
        let dest = dir.appendingPathComponent("\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
        let duration = Self.audioDuration(of: dest)
        return ("\(ideaID.uuidString)/\(dest.lastPathComponent)", size ?? 0, duration)
    }

    static func audioDuration(of url: URL) -> Double? {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    // MARK: - 存储(设置页占用统计)

    struct StorageUsage {
        var images: Int64 = 0
        var audio: Int64 = 0
        var others: Int64 = 0
        var total: Int64 { images + audio + others }
        var humanReadable: String {
            ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        }
    }

    func computeUsage() -> StorageUsage {
        var usage = StorageUsage()
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: files.root, includingPropertiesForKeys: [.fileSizeKey]) else {
            return usage
        }
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let ext = url.pathExtension.lowercased()
            if ext == "jpg" || ext == "jpeg" || ext == "png" || ext == "heic" {
                usage.images += Int64(size)
            } else if ext == "m4a" || ext == "wav" || ext == "mp3" {
                usage.audio += Int64(size)
            } else {
                usage.others += Int64(size)
            }
        }
        return usage
    }
}

import Flutter
import UIKit
import MediaPlayer
import AVFoundation

final class BonbonNowPlayingBridge: NSObject {
    static let shared = BonbonNowPlayingBridge()

    private let nowPlayingURL = URL(string: "https://c34.radioboss.fm/api/info/1015?key=QG5S5BO9HSKG")!
    private let coverBaseURL = "https://bonbonradio.net/wp-content/uploads/radio-covers/"
    private let defaultCoverURL = URL(string: "https://bonbonradio.net/wp-content/uploads/radio-covers/default.jpeg")!

    private var timer: Timer?
    private var currentArtworkURL: String = ""
    private(set) var currentTitle: String = "Live Stream"
    private(set) var currentArtist: String = "Bonbon Radio"
    private(set) var currentAlbumKey: String = ""
    private(set) var currentCoverURL: String = "https://bonbonradio.net/wp-content/uploads/radio-covers/default.jpeg"

    func start() {
        configureAudioSession()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        refresh(forceArtwork: true)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.refresh(forceArtwork: false)
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("BonbonNowPlayingBridge audio session error: \(error)")
        }
    }

    private func normalizeCoverKey(_ value: String) -> String {
        let lowercased = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let replaced = lowercased
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
        return replaced
    }

    private func isJingle(artist: String, title: String, album: String) -> Bool {
        let combined = "\(artist) \(title) \(album)".lowercased()
        return combined.contains("jingle")
    }

    private func resolveCover(album: String, artist: String, title: String) -> URL {
        if isJingle(artist: artist, title: title, album: album) {
            return defaultCoverURL
        }

        let key = !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? album
            : artist

        let normalized = normalizeCoverKey(key)
        if normalized.isEmpty {
            return defaultCoverURL
        }

        return URL(string: "\(coverBaseURL)\(normalized).jpeg") ?? defaultCoverURL
    }

    private func refresh(forceArtwork: Bool) {
        URLSession.shared.dataTask(with: nowPlayingURL) { [weak self] data, _, error in
            guard let self = self else { return }
            guard error == nil, let data = data else { return }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }

                let currentTrackInfo = json["currenttrack_info"] as? [String: Any]
                let attributes = currentTrackInfo?["@attributes"] as? [String: Any]

                var artist = (attributes?["ARTIST"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                var title = (attributes?["TITLE"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let album = (attributes?["ALBUM"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                let rawNowPlaying = (json["nowplaying"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                if (artist.isEmpty || title.isEmpty), !rawNowPlaying.isEmpty {
                    if let range = rawNowPlaying.range(of: " - ") {
                        if artist.isEmpty {
                            artist = String(rawNowPlaying[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        if title.isEmpty {
                            title = String(rawNowPlaying[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } else if title.isEmpty {
                        title = rawNowPlaying
                    }
                }

                if artist.isEmpty {
                    artist = "Bonbon Radio"
                }

                if title.isEmpty {
                    title = "Live Stream"
                }

                let coverURL = self.resolveCover(album: album, artist: artist, title: title)

                self.currentTitle = title
                self.currentArtist = artist
                self.currentAlbumKey = album
                self.currentCoverURL = coverURL.absoluteString

                self.publishNowPlaying(title: title, artist: artist, artworkURL: coverURL, forceArtwork: forceArtwork || self.currentArtworkURL != coverURL.absoluteString)
            } catch {
                print("BonbonNowPlayingBridge metadata parse error: \(error)")
            }
        }.resume()
    }

    private func publishNowPlaying(title: String, artist: String, artworkURL: URL, forceArtwork: Bool) {
        DispatchQueue.main.async {
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyTitle] = title
            info[MPMediaItemPropertyArtist] = artist
            info[MPMediaItemPropertyAlbumTitle] = ""
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }

        guard forceArtwork else { return }

        URLSession.shared.dataTask(with: artworkURL) { data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }

            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }

            DispatchQueue.main.async {
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyTitle] = title
                info[MPMediaItemPropertyArtist] = artist
                info[MPMediaItemPropertyAlbumTitle] = ""
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                self.currentArtworkURL = artworkURL.absoluteString
            }
        }.resume()
    }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        BonbonNowPlayingBridge.shared.start()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    }
}
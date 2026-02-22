import AppKit
import Combine
import Foundation

final class MediaService: MediaProviding, @unchecked Sendable {
    var mediaStatePublisher: AnyPublisher<MediaState, Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = CurrentValueSubject<MediaState, Never>(.unknown)
    private let distributedCenter = DistributedNotificationCenter.default()

    private var musicObserver: NSObjectProtocol?
    private var spotifyObserver: NSObjectProtocol?

    func start() {
        guard musicObserver == nil, spotifyObserver == nil else { return }

        musicObserver = distributedCenter.addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handlePlayerInfo(notification.userInfo, source: "Music")
        }

        spotifyObserver = distributedCenter.addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handlePlayerInfo(notification.userInfo, source: "Spotify")
        }
    }

    func stop() {
        if let musicObserver {
            distributedCenter.removeObserver(musicObserver)
            self.musicObserver = nil
        }
        if let spotifyObserver {
            distributedCenter.removeObserver(spotifyObserver)
            self.spotifyObserver = nil
        }
    }

    func playPause() {
        if runAppleScript("tell application \"Music\" to playpause") {
            return
        }
        _ = runAppleScript("tell application \"Spotify\" to playpause")
    }

    func nextTrack() {
        if runAppleScript("tell application \"Music\" to next track") {
            return
        }
        _ = runAppleScript("tell application \"Spotify\" to next track")
    }

    func previousTrack() {
        if runAppleScript("tell application \"Music\" to previous track") {
            return
        }
        _ = runAppleScript("tell application \"Spotify\" to previous track")
    }

    private func handlePlayerInfo(_ userInfo: [AnyHashable: Any]?, source: String) {
        guard let userInfo else { return }

        let title = userInfo["Name"] as? String ?? "Unknown"
        let artist = userInfo["Artist"] as? String ?? ""
        let playerState = (userInfo["Player State"] as? String)?.lowercased() ?? ""
        let isPlaying = playerState == "playing"

        subject.send(
            MediaState(
                title: title,
                artist: artist,
                isPlaying: isPlaying,
                sourceApp: source
            )
        )
    }

    private func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }
}

import UIKit
import CarPlay
import MediaPlayer

@available(iOS 14.0, *)
final class BonbonCarPlayContentManager: NSObject, MPPlayableContentDataSource, MPPlayableContentDelegate {
    static let shared = BonbonCarPlayContentManager()

    private let liveIdentifier = "bonbonradio.live"
    private weak var interfaceController: CPInterfaceController?

    private override init() {
        super.init()
    }

    func connect(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        let manager = MPPlayableContentManager.shared()
        manager.dataSource = self
        manager.delegate = self
        manager.nowPlayingIdentifiers = [liveIdentifier]

        let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        var info = existing

        if info[MPMediaItemPropertyTitle] == nil {
            info[MPMediaItemPropertyTitle] = "Bonbon Radio"
        }

        if info[MPMediaItemPropertyArtist] == nil {
            info[MPMediaItemPropertyArtist] = "Live Stream"
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        manager.reloadData()
    }

    func disconnect() {
        interfaceController = nil
    }

    func numberOfChildItems(at indexPath: IndexPath) -> Int {
        if indexPath.count == 0 {
            return 1
        }
        return 0
    }

    func contentItem(at indexPath: IndexPath) -> MPContentItem? {
        guard indexPath.count == 1, indexPath.item == 0 else {
            return nil
        }

        let item = MPContentItem(identifier: liveIdentifier)
        item.title = "Bonbon Radio"
        item.subtitle = "Live Stream"
        item.isPlayable = true
        item.isStreamingContent = true

        if let url = URL(string: "https://bonbonradio.net/wp-content/uploads/radio-covers/default.jpeg") {
            item.artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 512, height: 512)) { _ in
                if let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    return image
                }
                return UIImage()
            }
        }

        return item
    }

    func playableContentManager(_ contentManager: MPPlayableContentManager,
                                initiatePlaybackOfContentItemAt indexPath: IndexPath,
                                completionHandler: @escaping (Error?) -> Void) {
        contentManager.nowPlayingIdentifiers = [liveIdentifier]
        interfaceController?.setRootTemplate(CPNowPlayingTemplate.shared, animated: true)
        completionHandler(nil)
    }

    func playableContentManager(_ contentManager: MPPlayableContentManager,
                                beginLoadingChildItems at: IndexPath,
                                completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil)
    }
}

@available(iOS 14.0, *)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.stopCommand.isEnabled = true

        BonbonCarPlayContentManager.shared.connect(interfaceController: interfaceController)

        let nowPlaying = CPNowPlayingTemplate.shared
        interfaceController.setRootTemplate(nowPlaying, animated: false)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        self.interfaceController = nil
        BonbonCarPlayContentManager.shared.disconnect()
    }
}
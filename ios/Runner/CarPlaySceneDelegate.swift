import UIKit
import CarPlay
import MediaPlayer

@available(iOS 14.0, *)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController

        configureRemoteCommands()
        activateNowPlaying()

        let template = CPNowPlayingTemplate.shared
        interfaceController.setRootTemplate(template, animated: false)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        self.interfaceController = nil
    }

    private func activateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [
            MPMediaItemPropertyTitle: "Bonbon Radio",
            MPMediaItemPropertyArtist: "Live Stream"
        ]
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
    }
}
import UIKit
import CarPlay
import MediaPlayer

@available(iOS 14.0, *)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var carWindow: CPWindow?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController
        self.carWindow = window

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.stopCommand.isEnabled = true

        let nowPlaying = CPNowPlayingTemplate.shared
        interfaceController.setRootTemplate(nowPlaying, animated: false)

        print("CarPlay connected")
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        print("CarPlay disconnected")
        self.interfaceController = nil
        self.carWindow = nil
    }
}

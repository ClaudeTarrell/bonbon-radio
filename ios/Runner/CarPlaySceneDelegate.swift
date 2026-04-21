import UIKit
import CarPlay
import MediaPlayer

@available(iOS 14.0, *)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var refreshTimer: Timer?
    private var listTemplate: CPListTemplate?

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

        let template = buildRootTemplate()
        self.listTemplate = template

        interfaceController.setRootTemplate(template, animated: false)

        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.refreshTemplate()
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        listTemplate = nil
        self.interfaceController = nil
    }

    private func buildRootTemplate() -> CPListTemplate {
        let liveItem = CPListItem(
            text: BonbonNowPlayingBridge.shared.currentTitle,
            detailText: BonbonNowPlayingBridge.shared.currentArtist
        )

        liveItem.handler = { [weak self] _, completion in
            self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true)
            completion()
        }

        let section = CPListSection(items: [liveItem])

        let template = CPListTemplate(title: "Bonbon Radio", sections: [section])

        let nowPlayingButton = CPBarButton(type: .text) { [weak self] _ in
            self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true)
        }
        nowPlayingButton.title = "Now Playing"

        template.trailingNavigationBarButtons = [nowPlayingButton]
        template.tabTitle = "Bonbon Radio"

        return template
    }

    private func refreshTemplate() {
        guard let template = listTemplate else { return }

        let updatedItem = CPListItem(
            text: BonbonNowPlayingBridge.shared.currentTitle,
            detailText: BonbonNowPlayingBridge.shared.currentArtist
        )

        updatedItem.handler = { [weak self] _, completion in
            self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true)
            completion()
        }

        let section = CPListSection(items: [updatedItem])
        template.updateSections([section])
    }
}
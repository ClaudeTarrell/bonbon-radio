import Flutter
import UIKit
import CarPlay

class SceneDelegate: FlutterSceneDelegate, CPTemplateApplicationSceneDelegate {
  private var interfaceController: CPInterfaceController?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController,
    to window: CPWindow
  ) {
    self.interfaceController = interfaceController
    interfaceController.setRootTemplate(makeRootTemplate(), animated: false, completion: nil)
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController,
    from window: CPWindow
  ) {
    self.interfaceController = nil
  }

  private func makeRootTemplate() -> CPTemplate {
    let liveItem = CPListItem(
      text: "Bonbon Radio Live",
      detailText: "Öffnet die Now Playing Ansicht"
    )

    liveItem.handler = { [weak self] _, completion in
      self?.interfaceController?.pushTemplate(
        CPNowPlayingTemplate.shared,
        animated: true,
        completion: nil
      )
      completion()
    }

    let section = CPListSection(items: [liveItem])
    let listTemplate = CPListTemplate(title: "Bonbon Radio", sections: [section])
    listTemplate.tabTitle = "Radio"

    return listTemplate
  }
}
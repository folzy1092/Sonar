import SafariServices
import UIKit

/// Страница установки: SFSafariViewController на http://127.0.0.1:PORT/install передаёт ссылку
/// `itms-services` в iOS (как IPA Hub). Показывается поверх всего, что открыто, — даже над листом
/// «Обновление»; закрывается, когда iOS начала качать.
@MainActor
final class InstallPage {
    static let shared = InstallPage()

    private weak var controller: SFSafariViewController?

    func show(_ url: URL) {
        hide(animated: false)
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor(Theme.accent)
        self.controller = controller
        Self.topController()?.present(controller, animated: true)
    }

    func hide(animated: Bool = true) {
        guard let controller else { return }
        self.controller = nil
        if controller.presentingViewController != nil {
            controller.dismiss(animated: animated)
        }
    }

    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

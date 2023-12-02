// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

protocol DownloadsNavigationHandler: AnyObject {
    /// Handles the possibile navigations for a file.
    /// The source view is the view used to display a popover for the share controller.
    func handleFile(_ file: DownloadedFile, sourceView: UIView)

    /// Shows a UIDocumentInteractionController for the selected file.
    func showDocument(file: DownloadedFile)
}

class DownloadsCoordinator: BaseCoordinator, ParentCoordinatorDelegate, DownloadsNavigationHandler, UIDocumentInteractionControllerDelegate {
    // MARK: - Properties

    private weak var parentCoordinator: LibraryCoordinatorDelegate?
    private let profile: Profile

    // MARK: - Initializers

    init(
        router: Router,
        profile: Profile,
        parentCoordinator: LibraryCoordinatorDelegate?
    ) {
        self.parentCoordinator = parentCoordinator
        self.profile = profile
        super.init(router: router)
    }

    // MARK: - DownloadsNavigationHandler

    func handleFile(_ file: DownloadedFile, sourceView: UIView) {
        guard file.canShowInWebView
        else {
            startShare(file: file, sourceView: sourceView)
            return
        }
        parentCoordinator?.libraryPanel(didSelectURL: file.path, visitType: .typed)
    }

    private func startShare(file: DownloadedFile, sourceView: UIView) {
        guard !childCoordinators.contains(where: { $0 is ShareExtensionCoordinator }) else { return }
        let coordinator = makeShareExtensionCoordinator()
        coordinator.start(url: file.path, sourceView: sourceView)
    }

    private func makeShareExtensionCoordinator() -> ShareExtensionCoordinator {
        let coordinator = ShareExtensionCoordinator(
            alertContainer: UIView(),
            router: router,
            profile: profile,
            parentCoordinator: self
        )
        add(child: coordinator)
        return coordinator
    }

    func showDocument(file: DownloadedFile) {
        let docController = UIDocumentInteractionController(url: file.path)
        docController.delegate = self
        docController.presentPreview(animated: true)
    }

    // MARK: - ParentCoordinatorDelegate

    func didFinish(from childCoordinator: Coordinator) {
        remove(child: childCoordinator)
    }

    // MARK: - UIDocumentInteractionControllerDelegate

    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return router.rootViewController ?? UIViewController()
    }
}

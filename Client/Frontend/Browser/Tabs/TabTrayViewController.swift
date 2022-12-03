// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Shared
import Storage
import Foundation

enum TabTrayViewAction {
    case addTab
    case deleteTab
}

// swiftlint:disable class_delegate_protocol
protocol TabTrayViewDelegate: UIViewController {
    func didTogglePrivateMode(_ togglePrivateModeOn: Bool)
    func performToolbarAction(_ action: TabTrayViewAction, sender: UIBarButtonItem)
}
// swiftlint:enable class_delegate_protocol

class TabTrayViewController: UIViewController, Themeable {

    struct UX {
        struct NavigationMenu {
            static let height: CGFloat = 32
            static let width: CGFloat = 343
        }
    }

    // MARK: - Variables
    var viewModel: TabTrayViewModel
    var openInNewTab: ((_ url: URL, _ isPrivate: Bool) -> Void)?
    var didSelectUrl: ((_ url: URL, _ visitType: VisitType) -> Void)?
    var notificationCenter: NotificationProtocol
    var nimbus: FxNimbus
    var themeManager: ThemeManager
    var themeObserver: NSObjectProtocol?

    // MARK: - UI Elements
    // Buttons & Menus
    private lazy var deleteButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: UIImage.templateImageNamed(ImageIdentifiers.tabTrayDelete),
                                     style: .plain,
                                     target: self,
                                     action: #selector(didTapDeleteTabs(_:)))
        button.accessibilityIdentifier = "closeAllTabsButtonTabTray"
        button.accessibilityLabel = .AppMenu.Toolbar.TabTrayDeleteMenuButtonAccessibilityLabel
        return button
    }()

    private lazy var newTabButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: UIImage.templateImageNamed(ImageIdentifiers.tabTrayNewTab),
                                     style: .plain,
                                     target: self,
                                     action: #selector(didTapAddTab(_:)))
        button.accessibilityIdentifier = "newTabButtonTabTray"
        button.accessibilityLabel = .TabTrayAddTabAccessibilityLabel
        return button
    }()

    private lazy var doneButton: UIBarButtonItem = {
        let button = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(didTapDone))
        button.accessibilityIdentifier = "doneButtonTabTray"
        return button
    }()

    private lazy var syncTabButton: UIBarButtonItem = {
        let button = UIBarButtonItem(title: .FxASyncNow,
                                     style: .plain,
                                     target: self,
                                     action: #selector(didTapSyncTabs))

        button.accessibilityIdentifier = "syncTabsButtonTabTray"
        return button
    }()

    private lazy var syncLoadingView: UIStackView = {
        let syncingLabel = UILabel()
        syncingLabel.text = .SyncingMessageWithEllipsis
        syncingLabel.textColor = themeManager.currentTheme.colors.textPrimary

        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.color = themeManager.currentTheme.colors.textPrimary
        activityIndicator.startAnimating()

        let stackView = UIStackView(arrangedSubviews: [syncingLabel, activityIndicator])
        stackView.spacing = 12
        return stackView
    }()

    private lazy var flexibleSpace: UIBarButtonItem = {
        return UIBarButtonItem(barButtonSystemItem: .flexibleSpace,
                               target: nil,
                               action: nil)
    }()

    private lazy var fixedSpace: UIBarButtonItem = {
        let fixedSpace = UIBarButtonItem(barButtonSystemItem: .fixedSpace,
                               target: nil,
                               action: nil)
        fixedSpace.width = CGFloat(UX.NavigationMenu.height)
        return fixedSpace
    }()

    lazy var countLabel: UILabel = {
        let label = UILabel(frame: CGRect(width: 24, height: 24))
        label.font = TabsButtonUX.TitleFont
        label.layer.cornerRadius = TabsButtonUX.CornerRadius
        label.textAlignment = .center
        label.text = viewModel.normalTabsCount
        return label
    }()

    private lazy var bottomToolbarItems: [UIBarButtonItem] = {
        return [deleteButton, flexibleSpace, newTabButton]
    }()

    private lazy var bottomToolbarItemsForSync: [UIBarButtonItem] = {
        return [flexibleSpace, syncTabButton]
    }()

    private lazy var navigationMenu: UISegmentedControl = {
        var navigationMenu: UISegmentedControl
        if shouldUseiPadSetup() {
            navigationMenu = iPadNavigationMenuIdentifiers
        } else {
            navigationMenu = iPhoneNavigationMenuIdentifiers
        }

        navigationMenu.accessibilityIdentifier = "navBarTabTray"

        var segmentToFocus = viewModel.segmentToFocus
        if segmentToFocus == nil {
            segmentToFocus = viewModel.tabManager.selectedTab?.isPrivate ?? false ? .privateTabs : .tabs
        }
        navigationMenu.selectedSegmentIndex = segmentToFocus?.rawValue ?? TabTrayViewModel.Segment.tabs.rawValue
        navigationMenu.addTarget(self, action: #selector(panelChanged), for: .valueChanged)
        return navigationMenu
    }()

    private lazy var iPadNavigationMenuIdentifiers: UISegmentedControl = {
        return UISegmentedControl(items: TabTrayViewModel.Segment.allCases.map { $0.label })
    }()

    private lazy var iPhoneNavigationMenuIdentifiers: UISegmentedControl = {
        return UISegmentedControl(items: [
            TabTrayViewModel.Segment.tabs.image!.overlayWith(image: countLabel),
            TabTrayViewModel.Segment.privateTabs.image!,
            TabTrayViewModel.Segment.syncedTabs.image!])
    }()

    // Toolbars
    private lazy var navigationToolbar: UIToolbar = {
        let toolbar = UIToolbar()
        toolbar.delegate = self
        toolbar.setItems([UIBarButtonItem(customView: navigationMenu)], animated: false)
        toolbar.isTranslucent = false
        return toolbar
    }()

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    // MARK: - Initializers
    init(tabTrayDelegate: TabTrayDelegate? = nil,
         profile: Profile,
         tabToFocus: Tab? = nil,
         tabManager: TabManager,
         focusedSegment: TabTrayViewModel.Segment? = nil,
         themeManager: ThemeManager = AppContainer.shared.resolve(),
         and notificationCenter: NotificationProtocol = NotificationCenter.default,
         with nimbus: FxNimbus = FxNimbus.shared
    ) {
        self.nimbus = nimbus
        self.notificationCenter = notificationCenter
        self.themeManager = themeManager
        self.viewModel = TabTrayViewModel(tabTrayDelegate: tabTrayDelegate,
                                          profile: profile,
                                          tabToFocus: tabToFocus,
                                          tabManager: tabManager,
                                          segmentToFocus: focusedSegment)

        super.init(nibName: nil, bundle: nil)

        setupNotifications(forObserver: self,
                           observing: [.ProfileDidStartSyncing,
                                       .ProfileDidFinishSyncing,
                                       .UpdateLabelOnTabClosed])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        viewSetup()
        applyTheme()
        updatePrivateUIState()
        panelChanged()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // We expose the tab tray feature whenever it's going to be seen by the user
        nimbus.features.tabTrayFeature.recordExposure()

        if shouldUseiPadSetup() {
            navigationController?.isToolbarHidden = true
        } else {
            navigationController?.isToolbarHidden = false
            updateToolbarItems(forSyncTabs: viewModel.profile.hasSyncableAccount())
        }
    }

    private func viewSetup() {
        viewModel.syncedTabsController.remotePanelDelegate = self

        if shouldUseiPadSetup() {
            iPadViewSetup()
        } else {
            iPhoneViewSetup()
        }

        showPanel(viewModel.tabTrayView)
    }

    func updatePrivateUIState() {
        UserDefaults.standard.set(viewModel.tabManager.selectedTab?.isPrivate ?? false, forKey: "wasLastSessionPrivate")
    }

    fileprivate func iPadViewSetup() {
        navigationItem.leftBarButtonItem = deleteButton
        navigationItem.titleView = navigationMenu
        navigationItem.rightBarButtonItems = [doneButton, fixedSpace, newTabButton]

        navigationItem.titleView?.snp.makeConstraints { make in
            make.width.equalTo(343)
        }
    }

    fileprivate func iPhoneViewSetup() {
        navigationItem.rightBarButtonItem = doneButton

        view.addSubview(navigationToolbar)

        navigationToolbar.snp.makeConstraints { make in
            make.left.right.equalTo(view)
            make.top.equalTo(view.safeArea.top)
        }

        navigationMenu.snp.makeConstraints { make in
            make.width.lessThanOrEqualTo(UX.NavigationMenu.width)
            make.height.equalTo(UX.NavigationMenu.height)
        }
    }

    fileprivate func updateTitle() {
        if let newTitle = viewModel.navTitle(for: navigationMenu.selectedSegmentIndex,
                                             foriPhone: !shouldUseiPadSetup()) {
            navigationItem.title = newTitle
        }
    }

    @objc func panelChanged() {
        let segment = TabTrayViewModel.Segment(rawValue: navigationMenu.selectedSegmentIndex)
        switch segment {
        case .tabs:
            switchBetweenLocalPanels(withPrivateMode: false)
        case .privateTabs:
            switchBetweenLocalPanels(withPrivateMode: true)
        case .syncedTabs:
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .tap,
                                         object: .libraryPanel,
                                         value: .syncPanel,
                                         extras: nil)
            if children.first == viewModel.tabTrayView {
                hideCurrentPanel()
                updateToolbarItems(forSyncTabs: viewModel.profile.hasSyncableAccount())
                showPanel(viewModel.syncedTabsController)
            }
        default:
            return
        }
    }

    private func switchBetweenLocalPanels(withPrivateMode privateMode: Bool) {
        viewModel.tabManager.didChangedPanelSelection = true
        viewModel.tabManager.didAddNewTab = true
        if children.first != viewModel.tabTrayView {
            hideCurrentPanel()
            showPanel(viewModel.tabTrayView)
        }
        updateToolbarItems(forSyncTabs: viewModel.profile.hasSyncableAccount())
        viewModel.tabTrayView.didTogglePrivateMode(privateMode)
        updatePrivateUIState()
        updateTitle()
    }

    private func showPanel(_ panel: UIViewController) {
        addChild(panel)
        panel.beginAppearanceTransition(true, animated: true)
        view.addSubview(panel.view)
        view.bringSubviewToFront(navigationToolbar)
        let topEdgeInset = shouldUseiPadSetup() ? 0 : GridTabTrayControllerUX.NavigationToolbarHeight
        panel.additionalSafeAreaInsets = UIEdgeInsets(top: topEdgeInset, left: 0, bottom: 0, right: 0)
        panel.endAppearanceTransition()

        NSLayoutConstraint.activate([
            panel.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.view.topAnchor.constraint(equalTo: view.topAnchor),
            panel.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        panel.didMove(toParent: self)
        updateTitle()
    }

    private func hideCurrentPanel() {
        if let panel = children.first {
            panel.willMove(toParent: nil)
            panel.beginAppearanceTransition(false, animated: true)
            panel.view.removeFromSuperview()
            panel.endAppearanceTransition()
            panel.removeFromParent()
        }
    }

    private func updateToolbarItems(forSyncTabs showSyncItems: Bool = false) {
        if shouldUseiPadSetup() {
            if navigationMenu.selectedSegmentIndex == TabTrayViewModel.Segment.syncedTabs.rawValue {
                navigationItem.rightBarButtonItems = (showSyncItems ? [doneButton, fixedSpace, syncTabButton] : [doneButton])
                navigationItem.leftBarButtonItem = nil
            } else {
                navigationItem.rightBarButtonItems = [doneButton, fixedSpace, newTabButton]
                navigationItem.leftBarButtonItem = deleteButton
            }
        } else {
            var newToolbarItems: [UIBarButtonItem]? = bottomToolbarItems
            if navigationMenu.selectedSegmentIndex == TabTrayViewModel.Segment.syncedTabs.rawValue {
                newToolbarItems = showSyncItems ? bottomToolbarItemsForSync : nil
            }
            setToolbarItems(newToolbarItems, animated: true)
        }
    }

    private func updateButtonTitle(_ notification: Notification) {
        switch notification.name {
        case .ProfileDidStartSyncing:
            // Update Sync Tab button
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.syncTabButton.isEnabled = false
                self.syncTabButton.customView = self.syncLoadingView
            }
        case .ProfileDidFinishSyncing:
            // Update Sync Tab button
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.syncTabButton.customView = nil
                self.syncTabButton.title = .FxASyncNow
                self.syncTabButton.isEnabled = true
            }
        default:
            break
        }
    }

    // MARK: - Themable

    func applyTheme() {
        view.backgroundColor = themeManager.currentTheme.colors.layer4
        navigationToolbar.barTintColor = themeManager.currentTheme.colors.layer1
        viewModel.syncedTabsController.applyTheme()
    }
}

// MARK: - Notifiable protocol
extension TabTrayViewController: Notifiable {
    func handleNotifications(_ notification: Notification) {
        ensureMainThread { [weak self] in
            switch notification.name {
            case .ProfileDidStartSyncing, .ProfileDidFinishSyncing:
                self?.updateButtonTitle(notification)
            case .UpdateLabelOnTabClosed:
                guard let label = self?.countLabel else { return }
                self?.countLabel.text = self?.viewModel.normalTabsCount
                self?.iPhoneNavigationMenuIdentifiers.setImage(
                    UIImage(named: ImageIdentifiers.navTabCounter)!.overlayWith(image: label),
                    forSegmentAt: 0)
            default: break
            }
        }
    }
}

// MARK: - UIToolbarDelegate
extension TabTrayViewController: UIToolbarDelegate {
    func position(for bar: UIBarPositioning) -> UIBarPosition {
        return .topAttached
    }
}

// MARK: - Adaptive & Popover Presentation Delegates
extension TabTrayViewController: UIAdaptivePresentationControllerDelegate, UIPopoverPresentationControllerDelegate {
    // Returning None here, for the iPhone makes sure that the Popover is actually presented as a
    // Popover and not as a full-screen modal, which is the default on compact device classes.
    func adaptivePresentationStyle(for controller: UIPresentationController,
                                   traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        if shouldUseiPadSetup() {
            return .overFullScreen
        }
        return .none
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        notificationCenter.post(name: .TabsTrayDidClose)
        TelemetryWrapper.recordEvent(category: .action, method: .close, object: .tabTray)
    }
}

// MARK: - Button actions
extension TabTrayViewController {
    @objc func didTapAddTab(_ sender: UIBarButtonItem) {
        viewModel.didTapAddTab(sender)
    }

    @objc func didTapDeleteTabs(_ sender: UIBarButtonItem) {
        viewModel.didTapDeleteTab(sender)
    }

    @objc func didTapSyncTabs(_ sender: UIBarButtonItem) {
        viewModel.didTapSyncTabs(sender)
    }

    @objc func didTapDone() {
        notificationCenter.post(name: .TabsTrayDidClose)
        self.dismiss(animated: true, completion: nil)
    }
}

// MARK: - RemoteTabsPanel : LibraryPanelDelegate
extension TabTrayViewController: RemotePanelDelegate {
    func remotePanelDidRequestToSignIn() {
        fxaSignInOrCreateAccountHelper()
    }

    func remotePanelDidRequestToCreateAccount() {
        fxaSignInOrCreateAccountHelper()
    }

    func remotePanelDidRequestToOpenInNewTab(_ url: URL, isPrivate: Bool) {
        TelemetryWrapper.recordEvent(category: .action, method: .open, object: .syncTab)
        self.openInNewTab?(url, isPrivate)
        self.dismissVC()
    }

    func remotePanel(didSelectURL url: URL, visitType: VisitType) {
        TelemetryWrapper.recordEvent(category: .action, method: .open, object: .syncTab)
        self.didSelectUrl?(url, visitType)
        self.dismissVC()
    }

    // Sign In and Create Account Helper
    func fxaSignInOrCreateAccountHelper() {
        let fxaParams = FxALaunchParams(query: ["entrypoint": "homepanel"])
        let controller = FirefoxAccountSignInViewController.getSignInOrFxASettingsVC(fxaParams,
                                                                                     flowType: .emailLoginFlow,
                                                                                     referringPage: .tabTray,
                                                                                     profile: viewModel.profile)
        (controller as? FirefoxAccountSignInViewController)?.shouldReload = { [weak self] in
            self?.viewModel.reloadRemoteTabs()
        }
        presentThemedViewController(navItemLocation: .Left,
                                    navItemText: .Close,
                                    vcBeingPresented: controller,
                                    topTabsVisible: UIDevice.current.userInterfaceIdiom == .pad)
    }
}

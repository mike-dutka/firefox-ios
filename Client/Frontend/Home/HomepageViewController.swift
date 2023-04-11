// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Shared
import UIKit
import Storage
import SyncTelemetry
import MozillaAppServices

class HomepageViewController: UIViewController, HomePanel, FeatureFlaggable {

    // MARK: - Typealiases
    private typealias a11y = AccessibilityIdentifiers.FirefoxHomepage

    // MARK: - Operational Variables
    weak var homePanelDelegate: HomePanelDelegate?
    weak var libraryPanelDelegate: LibraryPanelDelegate?
    weak var browserBarViewDelegate: BrowserBarViewDelegate? {
        didSet {
            viewModel.jumpBackInViewModel.browserBarViewDelegate = browserBarViewDelegate
        }
    }

    var notificationCenter: NotificationProtocol = NotificationCenter.default

    private var viewModel: HomepageViewModel
    private var contextMenuHelper: HomepageContextMenuHelper
    private var tabManager: TabManagerProtocol
    private var urlBar: URLBarViewProtocol
    private var userDefaults: UserDefaultsInterface
    private lazy var wallpaperView: WallpaperBackgroundView = .build { _ in }
    private var jumpBackInContextualHintViewController: ContextualHintViewController
    private var syncTabContextualHintViewController: ContextualHintViewController
    private var collectionView: UICollectionView! = nil

    // Background for status bar
    private lazy var statusBarView: UIView = {
        let statusBarFrame = statusBarFrame ?? CGRect.zero
        let statusBarView = UIView(frame: statusBarFrame)
        view.addSubview(statusBarView)
        return statusBarView
    }()

    // Content stack views contains collection view.
    lazy var contentStackView: UIStackView = .build { stackView in
        stackView.backgroundColor = .clear
        stackView.axis = .vertical
    }

    var currentTab: Tab? {
        return tabManager.selectedTab
    }

    // MARK: - Initializers
    init(profile: Profile,
         tabManager: TabManagerProtocol,
         urlBar: URLBarViewProtocol,
         userDefaults: UserDefaultsInterface = UserDefaults.standard
    ) {
        self.urlBar = urlBar
        self.tabManager = tabManager
        self.userDefaults = userDefaults
        let isPrivate = tabManager.selectedTab?.isPrivate ?? true
        self.viewModel = HomepageViewModel(profile: profile,
                                           isPrivate: isPrivate,
                                           tabManager: tabManager,
                                           urlBar: urlBar)

        let jumpBackInContextualViewModel = ContextualHintViewModel(forHintType: .jumpBackIn,
                                                                    with: viewModel.profile)
        self.jumpBackInContextualHintViewController = ContextualHintViewController(with: jumpBackInContextualViewModel)
        let syncTabContextualViewModel = ContextualHintViewModel(forHintType: .jumpBackInSyncedTab,
                                                                 with: viewModel.profile)
        self.syncTabContextualHintViewController = ContextualHintViewController(with: syncTabContextualViewModel)
        self.contextMenuHelper = HomepageContextMenuHelper(viewModel: viewModel)
        super.init(nibName: nil, bundle: nil)

        contextMenuHelper.delegate = self
        contextMenuHelper.getPopoverSourceRect = { [weak self] popoverView in
            guard let self = self else { return CGRect() }
            return self.getPopoverSourceRect(sourceView: popoverView)
        }

        setupNotifications(forObserver: self,
                           observing: [.HomePanelPrefsChanged,
                                       .TabsPrivacyModeChanged,
                                       .WallpaperDidChange])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        jumpBackInContextualHintViewController.stopTimer()
        syncTabContextualHintViewController.stopTimer()
        notificationCenter.removeObserver(self)
    }

    // MARK: - View lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        configureWallpaperView()
        configureContentStackView()
        configureCollectionView()

        // Delay setting up the view model delegate to ensure the views have been configured first
        viewModel.delegate = self

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        applyTheme()
        setupSectionsAction()
        reloadView()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        jumpBackInContextualHintViewController.stopTimer()
        syncTabContextualHintViewController.stopTimer()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        wallpaperView.updateImageForOrientationChange()

        if UIDevice.current.userInterfaceIdiom == .pad {
            reloadOnRotation()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTheme()

        if previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass
            || previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass {
            reloadOnRotation()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // make sure the keyboard is dismissed when wallpaper onboarding is shown
        // or is StartAtHome case
        // Can be removed once underlying problem is solved (FXIOS-4904)
        if let presentedViewController = presentedViewController,
           presentedViewController.isKind(of: BottomSheetViewController.self) || tabManager.isStartingAtHome {
            self.dismissKeyboard()
        }
    }

    // MARK: - Layout

    func configureCollectionView() {
        collectionView = UICollectionView(frame: view.bounds,
                                          collectionViewLayout: createLayout())

        HomepageSectionType.cellTypes.forEach {
            collectionView.register($0, forCellWithReuseIdentifier: $0.cellIdentifier)
        }
        collectionView.register(LabelButtonHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: LabelButtonHeaderView.cellIdentifier)

        collectionView.keyboardDismissMode = .onDrag
        collectionView.addGestureRecognizer(longPressRecognizer)
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.showsVerticalScrollIndicator = false
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.accessibilityIdentifier = a11y.collectionView
        contentStackView.addArrangedSubview(collectionView)
    }

    func configureContentStackView() {
        view.addSubview(contentStackView)
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: view.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    func configureWallpaperView() {
        view.addSubview(wallpaperView)
        NSLayoutConstraint.activate([
            wallpaperView.topAnchor.constraint(equalTo: view.topAnchor),
            wallpaperView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wallpaperView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            wallpaperView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        view.sendSubviewToBack(wallpaperView)
    }

    func createLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewCompositionalLayout { [weak self]
            (sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in

            guard let self = self,
                  let viewModel = self.viewModel.getSectionViewModel(shownSection: sectionIndex),
                  viewModel.shouldShow
            else { return nil }
            return viewModel.section(for: layoutEnvironment.traitCollection)
        }
        return layout
    }

    // MARK: Long press

    private lazy var longPressRecognizer: UILongPressGestureRecognizer = {
        return UILongPressGestureRecognizer(target: self, action: #selector(longPress))
    }()

    @objc fileprivate func longPress(_ longPressGestureRecognizer: UILongPressGestureRecognizer) {
        guard longPressGestureRecognizer.state == .began else { return }

        let point = longPressGestureRecognizer.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point),
              let viewModel = viewModel.getSectionViewModel(shownSection: indexPath.section) as? HomepageSectionHandler
        else { return }

        viewModel.handleLongPress(with: collectionView, indexPath: indexPath)
    }

    // MARK: - Homepage view cycle
    /// Normal viewcontroller view cycles cannot be relied on the homepage since the current way of showing and hiding the homepage is through alpha.
    /// This is a problem that need to be fixed but until then we have to rely on the methods here.

    func homepageWillAppear(isZeroSearch: Bool) {
        viewModel.isZeroSearch = isZeroSearch
        viewModel.recordViewAppeared()
    }

    func homepageDidAppear() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.displayWallpaperSelector()
            if self?.tabManager.isStartingAtHome ?? false {
                self?.dismissKeyboard()
                self?.tabManager.isStartingAtHome = false
            }
        }
    }

    func homepageWillDisappear() {
        jumpBackInContextualHintViewController.stopTimer()
        syncTabContextualHintViewController.stopTimer()
        viewModel.recordViewDisappeared()
    }

    // MARK: - Helpers

    /// On iPhone, we call reloadOnRotation when the trait collection has changed, to ensure calculation
    /// is done with the new trait. On iPad, trait collection doesn't change from portrait to landscape (and vice-versa)
    /// since it's `.regular` on both. We reloadOnRotation from viewWillTransition in that case.
    private func reloadOnRotation() {
        if let _ = presentedViewController as? PhotonActionSheet {
            presentedViewController?.dismiss(animated: false, completion: nil)
        }

        // Force the entire collectionview to re-layout
        viewModel.refreshData(for: traitCollection)
        collectionView.reloadData()
        collectionView.collectionViewLayout.invalidateLayout()

        // This pushes a reload to the end of the main queue after all the work associated with
        // rotating has been completed. This is important because some of the cells layout are
        // based on the screen state
        DispatchQueue.main.async {
            self.collectionView.reloadData()
        }
    }

    private func adjustPrivacySensitiveSections(notification: Notification) {
        guard let dict = notification.object as? NSDictionary,
              let isPrivate = dict[Tab.privateModeKey] as? Bool
        else { return }

        viewModel.isPrivate = isPrivate
        reloadView()
    }

    func applyTheme() {
        view.backgroundColor = UIColor.theme.homePanel.topSitesBackground
        // TODO: Remove this once the new theme system is implemented on the homepage FXIOS-4882
        reloadView()
    }

    func scrollToTop(animated: Bool = false) {
        collectionView?.setContentOffset(.zero, animated: animated)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        dismissKeyboard()
    }

    @objc private func dismissKeyboard() {
        if currentTab?.lastKnownUrl?.absoluteString.hasPrefix("internal://") ?? false {
            urlBar.leaveOverlayMode()
        }
    }

    func updatePocketCellsWithVisibleRatio(cells: [UICollectionViewCell], relativeRect: CGRect) {
        guard let window = UIWindow.keyWindow else { return }
        for cell in cells {
            // For every story cell get it's frame relative to the window
            let targetRect = cell.superview.map { window.convert(cell.frame, from: $0) } ?? .zero

            // TODO: If visibility ratio is over 50% sponsored content can be marked as seen by the user
            _ = targetRect.visibilityRatio(relativeTo: relativeRect)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Find visible pocket cells that holds pocket stories
        let cells = self.collectionView.visibleCells.filter { $0.reuseIdentifier == PocketStandardCell.cellIdentifier }

        // Relative frame is the collectionView frame plus the status bar height
        let relativeRect = CGRect(
            x: collectionView.frame.minX,
            y: collectionView.frame.minY,
            width: collectionView.frame.width,
            height: collectionView.frame.height + UIWindow.statusBarHeight
        )
        updatePocketCellsWithVisibleRatio(cells: cells, relativeRect: relativeRect)

        updateStatusBar()
    }

    private func showSiteWithURLHandler(_ url: URL, isGoogleTopSite: Bool = false) {
        let visitType = VisitType.bookmark
        homePanelDelegate?.homePanel(didSelectURL: url, visitType: visitType, isGoogleTopSite: isGoogleTopSite)
    }

    func displayWallpaperSelector() {
        let wallpaperManager = WallpaperManager(userDefaults: userDefaults)
        guard wallpaperManager.canOnboardingBeShown(using: viewModel.profile),
              canModalBePresented
        else { return }

        self.dismissKeyboard()

        let viewModel = WallpaperSelectorViewModel(wallpaperManager: wallpaperManager, openSettingsAction: {
            self.homePanelDidRequestToOpenSettings(at: .wallpaper)
        })
        let viewController = WallpaperSelectorViewController(viewModel: viewModel)
        var bottomSheetViewModel = BottomSheetViewModel()
        bottomSheetViewModel.shouldDismissForTapOutside = false
        let bottomSheetVC = BottomSheetViewController(
            viewModel: bottomSheetViewModel,
            childViewController: viewController
        )

        self.present(bottomSheetVC, animated: false, completion: nil)
        userDefaults.set(true, forKey: PrefsKeys.Wallpapers.OnboardingSeenKey)
    }

    // Check if we already present something on top of the homepage,
    // and if the homepage is actually being shown to the user
    private var canModalBePresented: Bool {
        return presentedViewController == nil && view.alpha == 1
    }

    // MARK: - Contextual hint

    private func prepareJumpBackInContextualHint(onView headerView: LabelButtonHeaderView) {
        guard jumpBackInContextualHintViewController.shouldPresentHint(),
              !viewModel.shouldDisplayHomeTabBanner
        else { return }

        jumpBackInContextualHintViewController.configure(
            anchor: headerView.titleLabel,
            withArrowDirection: .down,
            andDelegate: self,
            presentedUsing: { self.presentContextualHint(contextualHintViewController: self.jumpBackInContextualHintViewController) },
            withActionBeforeAppearing: { self.contextualHintPresented(type: .jumpBackIn) },
            andActionForButton: { self.openTabsSettings() })
    }

    private func prepareSyncedTabContextualHint(onCell cell: SyncedTabCell) {
        guard syncTabContextualHintViewController.shouldPresentHint(),
              featureFlags.isFeatureEnabled(.contextualHintForJumpBackInSyncedTab, checking: .buildOnly)
        else {
            syncTabContextualHintViewController.unconfigure()
            return
        }

        syncTabContextualHintViewController.configure(
            anchor: cell.getContextualHintAnchor(),
            withArrowDirection: .down,
            andDelegate: self,
            presentedUsing: { self.presentContextualHint(contextualHintViewController: self.syncTabContextualHintViewController) },
            withActionBeforeAppearing: { self.contextualHintPresented(type: .jumpBackInSyncedTab) })
    }

    @objc private func presentContextualHint(contextualHintViewController: ContextualHintViewController) {
        guard BrowserViewController.foregroundBVC().searchController == nil, canModalBePresented else {
            contextualHintViewController.stopTimer()
            return
        }

        present(contextualHintViewController, animated: true, completion: nil)

        UIAccessibility.post(notification: .layoutChanged, argument: contextualHintViewController)
    }
}

// MARK: - CollectionView Data Source

extension HomepageViewController: UICollectionViewDelegate, UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader,
              let headerView = collectionView.dequeueReusableSupplementaryView(
                ofKind: UICollectionView.elementKindSectionHeader,
                withReuseIdentifier: LabelButtonHeaderView.cellIdentifier,
                for: indexPath) as? LabelButtonHeaderView,
              let sectionViewModel = viewModel.getSectionViewModel(shownSection: indexPath.section)
        else { return UICollectionReusableView() }

        // Jump back in header specific setup
        if sectionViewModel.sectionType == .jumpBackIn {
            viewModel.jumpBackInViewModel.sendImpressionTelemetry()
            prepareJumpBackInContextualHint(onView: headerView)
        }

        // Configure header only if section is shown
        let headerViewModel = sectionViewModel.shouldShow ? sectionViewModel.headerViewModel : LabelButtonHeaderViewModel.emptyHeader
        headerView.configure(viewModel: headerViewModel)
        return headerView
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return viewModel.shownSections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewModel.getSectionViewModel(shownSection: section)?.numberOfItemsInSection() ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let viewModel = viewModel.getSectionViewModel(shownSection: indexPath.section) as? HomepageSectionHandler else {
            return UICollectionViewCell()
        }

        return viewModel.configure(collectionView, at: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let viewModel = viewModel.getSectionViewModel(shownSection: indexPath.section) as? HomepageSectionHandler else { return }
        viewModel.didSelectItem(at: indexPath, homePanelDelegate: homePanelDelegate, libraryPanelDelegate: libraryPanelDelegate)
    }
}

// MARK: - Actions Handling

private extension HomepageViewController {

    // Setup all the tap and long press actions on cells in each sections
    private func setupSectionsAction() {

        // Header view
        viewModel.headerViewModel.onTapAction = { _ in
            // No action currently set if the logo button is tapped.
        }

        // Message card
        viewModel.messageCardViewModel.dismissClosure = { [weak self] in
            self?.reloadView()
        }

        // Top sites
        viewModel.topSiteViewModel.tilePressedHandler = { [weak self] site, isGoogle in
            guard let url = site.url.asURL else { return }
            self?.showSiteWithURLHandler(url, isGoogleTopSite: isGoogle)
        }

        viewModel.topSiteViewModel.tileLongPressedHandler = { [weak self] (site, sourceView) in
            self?.contextMenuHelper.presentContextMenu(for: site, with: sourceView, sectionType: .topSites)
        }

        // Recently saved
        viewModel.recentlySavedViewModel.headerButtonAction = { [weak self] button in
            self?.openBookmarks(button)
        }

        // Jumpback in
        viewModel.jumpBackInViewModel.onTapGroup = { [weak self] tab in
            self?.homePanelDelegate?.homePanelDidRequestToOpenTabTray(withFocusedTab: tab)
        }

        viewModel.jumpBackInViewModel.headerButtonAction = { [weak self] button in
            self?.openTabTray(button)
        }

        viewModel.jumpBackInViewModel.syncedTabsShowAllAction = { [weak self] in
            self?.homePanelDelegate?.homePanelDidRequestToOpenTabTray(focusedSegment: .syncedTabs)

            var extras: [String: String]?
            if let isZeroSearch = self?.viewModel.isZeroSearch {
                extras = TelemetryWrapper.getOriginExtras(isZeroSearch: isZeroSearch)
            }
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .tap,
                                         object: .firefoxHomepage,
                                         value: .jumpBackInSectionSyncedTabShowAll,
                                         extras: extras)
        }

        viewModel.jumpBackInViewModel.openSyncedTabAction = { [weak self] tabURL in
            self?.homePanelDelegate?.homePanelDidRequestToOpenInNewTab(tabURL, isPrivate: false, selectNewTab: true)

            var extras: [String: String]?
            if let isZeroSearch = self?.viewModel.isZeroSearch {
                extras = TelemetryWrapper.getOriginExtras(isZeroSearch: isZeroSearch)
            }
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .tap,
                                         object: .firefoxHomepage,
                                         value: .jumpBackInSectionSyncedTabOpened,
                                         extras: extras)
        }

        viewModel.jumpBackInViewModel.prepareContextualHint = { [weak self] syncedTabCell in
            self?.prepareSyncedTabContextualHint(onCell: syncedTabCell)
        }

        // History highlights
        viewModel.historyHighlightsViewModel.onTapItem = { [weak self] highlight in
            guard let url = highlight.siteUrl else {
                self?.openHistoryHighlightsSearchGroup(item: highlight)
                return
            }

            self?.homePanelDelegate?.homePanel(didSelectURL: url,
                                               visitType: .link,
                                               isGoogleTopSite: false)
        }

        viewModel.historyHighlightsViewModel.historyHighlightLongPressHandler = { [weak self] (highlightItem, sourceView) in
            self?.contextMenuHelper.presentContextMenu(for: highlightItem,
                                                       with: sourceView,
                                                       sectionType: .historyHighlights)
        }

        viewModel.historyHighlightsViewModel.headerButtonAction = { [weak self] button in
            self?.openHistory(button)
        }

        // Pocket
        viewModel.pocketViewModel.onTapTileAction = { [weak self] url in
            self?.showSiteWithURLHandler(url)
        }

        viewModel.pocketViewModel.onLongPressTileAction = { [weak self] (site, sourceView) in
            self?.contextMenuHelper.presentContextMenu(for: site, with: sourceView, sectionType: .pocket)
        }

        viewModel.pocketViewModel.onScroll = { [weak self] cells in
            guard let window = UIWindow.keyWindow, let self = self else { return }
            let cells = self.collectionView.visibleCells.filter { $0.reuseIdentifier == PocketStandardCell.cellIdentifier }
            self.updatePocketCellsWithVisibleRatio(cells: cells, relativeRect: window.bounds)
        }

        // Customize home
        viewModel.customizeButtonViewModel.onTapAction = { [weak self] _ in
            self?.openCustomizeHomeSettings()
        }
    }

    private func openHistoryHighlightsSearchGroup(item: HighlightItem) {
        guard let groupItem = item.group else { return }

        var groupedSites = [Site]()
        for item in groupItem {
            groupedSites.append(buildSite(from: item))
        }
        let groupSite = ASGroup<Site>(searchTerm: item.displayTitle, groupedItems: groupedSites, timestamp: Date.now())

        let asGroupListViewModel = SearchGroupedItemsViewModel(asGroup: groupSite, presenter: .recentlyVisited)
        let asGroupListVC = SearchGroupedItemsViewController(viewModel: asGroupListViewModel, profile: viewModel.profile)

        let dismissableController: DismissableNavigationViewController
        dismissableController = DismissableNavigationViewController(rootViewController: asGroupListVC)

        self.present(dismissableController, animated: true, completion: nil)

        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .firefoxHomepage,
                                     value: .historyHighlightsGroupOpen,
                                     extras: nil)

        asGroupListVC.libraryPanelDelegate = libraryPanelDelegate
    }

    private func buildSite(from highlight: HighlightItem) -> Site {
        let itemURL = highlight.siteUrl?.absoluteString ?? ""
        return Site(url: itemURL, title: highlight.displayTitle)
    }

    func openTabTray(_ sender: UIButton) {
        homePanelDelegate?.homePanelDidRequestToOpenTabTray(withFocusedTab: nil)

        if sender.accessibilityIdentifier == a11y.MoreButtons.jumpBackIn {
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .tap,
                                         object: .firefoxHomepage,
                                         value: .jumpBackInSectionShowAll,
                                         extras: TelemetryWrapper.getOriginExtras(isZeroSearch: viewModel.isZeroSearch))
        }
    }

    func openBookmarks(_ sender: UIButton) {
        homePanelDelegate?.homePanelDidRequestToOpenLibrary(panel: .bookmarks)

        if sender.accessibilityIdentifier == a11y.MoreButtons.recentlySaved {
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .tap,
                                         object: .firefoxHomepage,
                                         value: .recentlySavedSectionShowAll,
                                         extras: TelemetryWrapper.getOriginExtras(isZeroSearch: viewModel.isZeroSearch))
        }
    }

    func openHistory(_ sender: UIButton) {
        homePanelDelegate?.homePanelDidRequestToOpenLibrary(panel: .history)

        if sender.accessibilityIdentifier == a11y.MoreButtons.historyHighlights {
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .tap,
                                         object: .firefoxHomepage,
                                         value: .historyHighlightsShowAll)

        }
    }

    func openCustomizeHomeSettings() {
        homePanelDelegate?.homePanelDidRequestToOpenSettings(at: .customizeHomepage)
        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .firefoxHomepage,
                                     value: .customizeHomepageButton)
    }

    func contextualHintPresented(type: ContextualHintType) {
        homePanelDelegate?.homePanelDidPresentContextualHintOf(type: type)
    }

    func openTabsSettings() {
        homePanelDelegate?.homePanelDidRequestToOpenSettings(at: .customizeTabs)
    }

    func getPopoverSourceRect(sourceView: UIView?) -> CGRect {
        let cellRect = sourceView?.frame ?? .zero
        let cellFrameInSuperview = self.collectionView?.convert(cellRect, to: self.collectionView) ?? .zero

        return CGRect(origin: CGPoint(x: cellFrameInSuperview.size.width / 2,
                                      y: cellFrameInSuperview.height / 2),
                      size: .zero)
    }
}

// MARK: FirefoxHomeContextMenuHelperDelegate
extension HomepageViewController: HomepageContextMenuHelperDelegate {
    func homePanelDidRequestToOpenInNewTab(_ url: URL, isPrivate: Bool, selectNewTab: Bool) {
        homePanelDelegate?.homePanelDidRequestToOpenInNewTab(url, isPrivate: isPrivate, selectNewTab: selectNewTab)
    }

    func homePanelDidRequestToOpenSettings(at settingsPage: AppSettingsDeeplinkOption) {
        homePanelDelegate?.homePanelDidRequestToOpenSettings(at: settingsPage)
    }
}

// MARK: - Status Bar Background
private extension HomepageViewController {

    var statusBarFrame: CGRect? {
        guard let keyWindow = UIWindow.keyWindow else { return nil }

        return keyWindow.windowScene?.statusBarManager?.statusBarFrame
    }

    // Returns a value between 0 and 1 which indicates how far the user has scrolled.
    // This is used as the alpha of the status bar background.
    // 0 = no status bar background shown
    // 1 = status bar background is opaque
    var scrollOffset: CGFloat {
        // Status bar height can be 0 on iPhone in landscape mode.
        guard let scrollView = collectionView,
              isBottomSearchBar,
              let statusBarHeight: CGFloat = statusBarFrame?.height,
              statusBarHeight > 0
        else { return 0 }

        // The scrollview content offset is automatically adjusted to account for the status bar.
        // We want to start showing the status bar background as soon as the user scrolls.
        var offset = (scrollView.contentOffset.y + statusBarHeight) / statusBarHeight

        if offset > 1 {
            offset = 1
        } else if offset < 0 {
            offset = 0
        }
        return offset
    }

    var isBottomSearchBar: Bool {
        guard SearchBarSettingsViewModel.isEnabled else { return false }

        return SearchBarSettingsViewModel(prefs: viewModel.profile.prefs).searchBarPosition == .bottom
    }

    func updateStatusBar() {
        let backgroundColor = UIColor.theme.homePanel.topSitesBackground
        statusBarView.backgroundColor = backgroundColor.withAlphaComponent(scrollOffset)

        if let statusBarFrame = statusBarFrame {
            statusBarView.frame = statusBarFrame
        }
    }
}

// MARK: - Popover Presentation Delegate

extension HomepageViewController: UIPopoverPresentationControllerDelegate {

    // Dismiss the popover if the device is being rotated.
    // This is used by the Share UIActivityViewController action sheet on iPad
    func popoverPresentationController(
        _ popoverPresentationController: UIPopoverPresentationController,
        willRepositionPopoverTo rect: UnsafeMutablePointer<CGRect>,
        in view: AutoreleasingUnsafeMutablePointer<UIView>
    ) {
        // Do not dismiss if the popover is a CFR
        guard !jumpBackInContextualHintViewController.isPresenting &&
                !syncTabContextualHintViewController.isPresenting else { return }
        popoverPresentationController.presentedViewController.dismiss(animated: false, completion: nil)
    }

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        return true
    }
}

// MARK: FirefoxHomeViewModelDelegate
extension HomepageViewController: HomepageViewModelDelegate {
    func reloadView() {
        ensureMainThread { [weak self] in
            // If the view controller is not visible ignore updates
            guard let self = self else { return }

            self.viewModel.refreshData(for: self.traitCollection)
            self.collectionView.reloadData()
            self.collectionView.collectionViewLayout.invalidateLayout()
        }
    }
}

// MARK: - Notifiable
extension HomepageViewController: Notifiable {
    func handleNotifications(_ notification: Notification) {
        ensureMainThread { [weak self] in
            guard let self = self else { return }

            switch notification.name {
            case .TabsPrivacyModeChanged:
                self.adjustPrivacySensitiveSections(notification: notification)

            case .HomePanelPrefsChanged,
                    .WallpaperDidChange:
                self.reloadView()

            default: break
            }
        }
    }
}
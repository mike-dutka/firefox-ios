/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared
import Storage
import XCGLogger
import Deferred

private struct HistoryPanelUX {
    static let WelcomeScreenItemTextColor = UIColor.Photon.Grey50
    static let WelcomeScreenItemWidth = 170
    static let IconSize = 23
    static let IconBorderColor = UIColor.Photon.Grey30
    static let IconBorderWidth: CGFloat = 0.5
}

private class FetchInProgressError: MaybeErrorType {
    internal var description: String {
        return "Fetch is already in-progress"
    }
}

class HistoryPanel: SiteTableViewController, HomePanel {
    enum Section: Int {
        case syncAndRecentlyClosed
        case today
        case yesterday
        case lastWeek
        case lastMonth

        static let count = 5

        var title: String? {
            switch self {
            case .today:
                return Strings.TableDateSectionTitleToday
            case .yesterday:
                return Strings.TableDateSectionTitleYesterday
            case .lastWeek:
                return Strings.TableDateSectionTitleLastWeek
            case .lastMonth:
                return Strings.TableDateSectionTitleLastMonth
            default:
                return nil
            }
        }
    }

    let QueryLimitPerFetch = 100

    var homePanelDelegate: HomePanelDelegate?

    var groupedSites = DateGroupedTableData<Site>()

    var refreshControl: UIRefreshControl?

    var syncDetailText = ""
    var currentSyncedDevicesCount = 0

    var currentFetchOffset = 0
    var isFetchInProgress = false

    var hasRecentlyClosed: Bool {
        return profile.recentlyClosedTabs.tabs.count > 0
    }

    lazy var emptyStateOverlayView: UIView = createEmptyStateOverlayView()

    lazy var longPressRecognizer: UILongPressGestureRecognizer = {
        return UILongPressGestureRecognizer(target: self, action: #selector(onLongPressGestureRecognized))
    }()

    // MARK: - Lifecycle
    override init(profile: Profile) {
        super.init(profile: profile)

        [ Notification.Name.FirefoxAccountChanged,
          Notification.Name.PrivateDataClearedHistory,
          Notification.Name.DynamicFontChanged ].forEach {
            NotificationCenter.default.addObserver(self, selector: #selector(onNotificationReceived), name: $0, object: nil)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.addGestureRecognizer(longPressRecognizer)
        tableView.accessibilityIdentifier = "History List"
        tableView.prefetchDataSource = self
        updateSyncedDevicesCount().uponQueue(.main) { result in
            self.updateNumberOfSyncedDevices(self.currentSyncedDevicesCount)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Add a refresh control if the user is logged in and the control was not added before. If the user is not
        // logged in, remove any existing control but only when it is not currently refreshing. Otherwise, wait for
        // the refresh to finish before removing the control.
        if profile.hasSyncableAccount() && refreshControl == nil {
            addRefreshControl()
        } else if refreshControl?.isRefreshing == false {
            removeRefreshControl()
        }

        if profile.hasSyncableAccount() {
            syncDetailText = " "
            updateSyncedDevicesCount().uponQueue(.main) { result in
                self.updateNumberOfSyncedDevices(self.currentSyncedDevicesCount)
            }
        } else {
            syncDetailText = ""
        }
    }

    // MARK: - Refreshing TableView

    func addRefreshControl() {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(onRefreshPulled), for: .valueChanged)
        refreshControl = control
        tableView.refreshControl = control
    }

    func removeRefreshControl() {
        tableView.refreshControl = nil
        refreshControl = nil
    }

    func endRefreshing() {
        // Always end refreshing, even if we failed!
        refreshControl?.endRefreshing()

        // Remove the refresh control if the user has logged out in the meantime
        if !profile.hasSyncableAccount() {
            removeRefreshControl()
        }
    }

    // MARK: - Loading data

    override func reloadData() {
        groupedSites = DateGroupedTableData<Site>()

        currentFetchOffset = 0
        fetchData().uponQueue(.main) { result in
            if let sites = result.successValue {
                for site in sites {
                    if let site = site, let latestVisit = site.latestVisit {
                        self.groupedSites.add(site, timestamp: TimeInterval.fromMicrosecondTimestamp(latestVisit.date))
                    }
                }

                self.tableView.reloadData()
                self.updateEmptyPanelState()
            }
        }
    }

    func fetchData() -> Deferred<Maybe<Cursor<Site>>> {
        guard !isFetchInProgress else {
            return deferMaybe(FetchInProgressError())
        }

        isFetchInProgress = true

        return profile.history.getSitesByLastVisit(limit: QueryLimitPerFetch, offset: currentFetchOffset) >>== { result in
            // Force 100ms delay between resolution of the last batch of results
            // and the next time `fetchData()` can be called.
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                self.currentFetchOffset += self.QueryLimitPerFetch
                self.isFetchInProgress = false
            }

            return deferMaybe(result)
        }
    }

    func resyncHistory() {
        profile.syncManager.syncHistory().uponQueue(.main) { result in
            self.endRefreshing()

            if result.isSuccess {
                self.reloadData()
            }

            self.updateSyncedDevicesCount().uponQueue(.main) { result in
                self.updateNumberOfSyncedDevices(self.currentSyncedDevicesCount)
            }
        }
    }

    func updateNumberOfSyncedDevices(_ count: Int) {
        if count > 0 {
            syncDetailText = String.localizedStringWithFormat(Strings.SyncedTabsTableViewCellDescription, count)
        } else {
            syncDetailText = ""
        }
        tableView.reloadRows(at: [IndexPath(row: 1, section: Section.syncAndRecentlyClosed.rawValue)], with: .automatic)
    }

    func updateSyncedDevicesCount() -> Success {
        guard profile.hasSyncableAccount() else {
            currentSyncedDevicesCount = 0
            return succeed()
        }

        return chainDeferred(profile.getCachedClientsAndTabs()) { tabsAndClients in
            self.currentSyncedDevicesCount = tabsAndClients.count
            return succeed()
        }
    }

    // MARK: - Actions

    func removeHistoryForURLAtIndexPath(indexPath: IndexPath) {
        guard let site = siteForIndexPath(indexPath) else {
            return
        }

        profile.history.removeHistoryForURL(site.url).uponQueue(.main) { result in
            self.tableView.beginUpdates()
            self.groupedSites.remove(site)
            self.tableView.deleteRows(at: [indexPath], with: .right)
            self.tableView.endUpdates()
            self.updateEmptyPanelState()
        }
    }

    func pinToTopSites(_ site: Site) {
        _ = profile.history.addPinnedTopSite(site).value
    }

    func navigateToSyncedTabs() {
        let nextController = RemoteTabsPanel(profile: profile)
        nextController.homePanelDelegate = homePanelDelegate
        refreshControl?.endRefreshing()
        navigationController?.pushViewController(nextController, animated: true)
    }

    func navigateToRecentlyClosed() {
        guard hasRecentlyClosed else {
            return
        }

        let nextController = RecentlyClosedTabsPanel(profile: profile)
        nextController.homePanelDelegate = homePanelDelegate
        refreshControl?.endRefreshing()
        navigationController?.pushViewController(nextController, animated: true)
    }

    // MARK: - Cell configuration

    func siteForIndexPath(_ indexPath: IndexPath) -> Site? {
        // First section is reserved for Sync.
        guard indexPath.section > Section.syncAndRecentlyClosed.rawValue else {
            return nil
        }

        let sitesInSection = groupedSites.itemsForSection(indexPath.section - 1)
        return sitesInSection[safe: indexPath.row]
    }

    func configureRecentlyClosed(_ cell: UITableViewCell, for indexPath: IndexPath) -> UITableViewCell {
        cell.accessoryType = .disclosureIndicator
        cell.textLabel?.text = Strings.RecentlyClosedTabsButtonTitle
        cell.detailTextLabel?.text = ""
        cell.imageView?.image = UIImage(named: "recently_closed")
        cell.imageView?.backgroundColor = UIColor.theme.homePanel.historyHeaderIconsBackground
        if !hasRecentlyClosed {
            cell.textLabel?.alpha = 0.5
            cell.imageView?.alpha = 0.5
            cell.selectionStyle = .none
        }
        cell.accessibilityIdentifier = "HistoryPanel.recentlyClosedCell"
        return cell
    }

    func configureSyncedTabs(_ cell: UITableViewCell, for indexPath: IndexPath) -> UITableViewCell {
        cell.accessoryType = .disclosureIndicator
        cell.textLabel?.text = Strings.SyncedTabsTableViewCellTitle
        cell.detailTextLabel?.text = syncDetailText
        cell.imageView?.image = UIImage(named: "synced_devices")
        cell.imageView?.backgroundColor = UIColor.theme.homePanel.historyHeaderIconsBackground
        cell.accessibilityIdentifier = "HistoryPanel.syncedDevicesCell"
        return cell
    }

    func configureSite(_ cell: UITableViewCell, for indexPath: IndexPath) -> UITableViewCell {
        if let site = siteForIndexPath(indexPath), let cell = cell as? TwoLineTableViewCell {
            cell.setLines(site.title, detailText: site.url)

            cell.imageView?.layer.borderColor = HistoryPanelUX.IconBorderColor.cgColor
            cell.imageView?.layer.borderWidth = HistoryPanelUX.IconBorderWidth
            cell.imageView?.setIcon(site.icon, forURL: site.tileURL, completed: { (color, url) in
                if site.tileURL == url {
                    cell.imageView?.image = cell.imageView?.image?.createScaled(CGSize(width: HistoryPanelUX.IconSize, height: HistoryPanelUX.IconSize))
                    cell.imageView?.backgroundColor = color
                    cell.imageView?.contentMode = .center
                }
            })
        }
        return cell
    }

    // MARK: - Selector callbacks

    @objc func onNotificationReceived(_ notification: Notification) {
        reloadData()

        switch notification.name {
        case .FirefoxAccountChanged, .PrivateDataClearedHistory:
            if profile.hasSyncableAccount() {
                resyncHistory()
            }
            break
        case .DynamicFontChanged:
            if emptyStateOverlayView.superview != nil {
                emptyStateOverlayView.removeFromSuperview()
            }
            emptyStateOverlayView = createEmptyStateOverlayView()
            resyncHistory()
            break
        default:
            // no need to do anything at all
            print("Error: Received unexpected notification \(notification.name)")
            break
        }
    }

    @objc func onLongPressGestureRecognized(_ longPressGestureRecognizer: UILongPressGestureRecognizer) {
        guard longPressGestureRecognizer.state == .began else { return }
        let touchPoint = longPressGestureRecognizer.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: touchPoint) else { return }

        if indexPath.section != Section.syncAndRecentlyClosed.rawValue {
            presentContextMenu(for: indexPath)
        }
    }

    @objc func onRefreshPulled() {
        refreshControl?.beginRefreshing()
        resyncHistory()
    }

    // MARK: - UITableViewDataSource
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // First section is for Sync/recently closed and always has 2 rows.
        guard section > Section.syncAndRecentlyClosed.rawValue else {
            return 2
        }

        return groupedSites.numberOfItemsForSection(section - 1)
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        // First section is for Sync/recently closed and has no title.
        guard section > Section.syncAndRecentlyClosed.rawValue else {
            return nil
        }

        // Ensure there are rows in this section.
        guard groupedSites.numberOfItemsForSection(section - 1) > 0 else {
            return nil
        }

        return Section(rawValue: section)?.title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        cell.accessoryType = .none

        // First section is reserved for Sync/recently closed.
        guard indexPath.section > Section.syncAndRecentlyClosed.rawValue else {
            cell.imageView?.layer.borderWidth = 0
            return indexPath.row == 0 ? configureRecentlyClosed(cell, for: indexPath) : configureSyncedTabs(cell, for: indexPath)
        }

        return configureSite(cell, for: indexPath)
    }

    // MARK: - UITableViewDelegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // First section is reserved for Sync/recently closed.
        guard indexPath.section > Section.syncAndRecentlyClosed.rawValue else {
            tableView.deselectRow(at: indexPath, animated: true)
            return indexPath.row == 0 ? navigateToRecentlyClosed() : navigateToSyncedTabs()
        }

        if let site = siteForIndexPath(indexPath), let url = URL(string: site.url) {
            if let homePanelDelegate = homePanelDelegate {
                homePanelDelegate.homePanel(self, didSelectURL: url, visitType: VisitType.typed)
            }
            return
        }
        print("Error: No site or no URL when selecting row.")
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.textColor = UIColor.theme.tableView.headerTextDark
            header.contentView.backgroundColor = UIColor.theme.tableView.headerBackground
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        // First section is for Sync/recently closed and its header has no view.
        guard section > Section.syncAndRecentlyClosed.rawValue else {
            return nil
        }

        // Ensure there are rows in this section.
        guard groupedSites.numberOfItemsForSection(section - 1) > 0 else {
            return nil
        }

        return super.tableView(tableView, viewForHeaderInSection: section)
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        // First section is for Sync/recently closed and its header has no height.
        guard section > Section.syncAndRecentlyClosed.rawValue else {
            return 0
        }

        // Ensure there are rows in this section.
        guard groupedSites.numberOfItemsForSection(section - 1) > 0 else {
            return 0
        }

        return super.tableView(tableView, heightForHeaderInSection: section)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        // Intentionally blank. Required to use UITableViewRowActions
    }

    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        if indexPath.section == Section.syncAndRecentlyClosed.rawValue {
            return []
        }
        let title = NSLocalizedString("Delete", tableName: "HistoryPanel", comment: "Action button for deleting history entries in the history panel.")

        let delete = UITableViewRowAction(style: .default, title: title, handler: { (action, indexPath) in
            self.removeHistoryForURLAtIndexPath(indexPath: indexPath)
        })
        return [delete]
    }

    // MARK: - Empty State
    func updateEmptyPanelState() {
        if groupedSites.isEmpty {
            if emptyStateOverlayView.superview == nil {
                tableView.addSubview(emptyStateOverlayView)
                emptyStateOverlayView.snp.makeConstraints { make -> Void in
                    make.left.right.bottom.equalTo(self.view)
                    make.top.equalTo(self.view).offset(100)
                }
            }
        } else {
            tableView.alwaysBounceVertical = true
            emptyStateOverlayView.removeFromSuperview()
        }
    }

    func createEmptyStateOverlayView() -> UIView {
        let overlayView = UIView()
        overlayView.backgroundColor = UIColor.theme.homePanel.panelBackground

        let welcomeLabel = UILabel()
        overlayView.addSubview(welcomeLabel)
        welcomeLabel.text = Strings.HistoryPanelEmptyStateTitle
        welcomeLabel.textAlignment = .center
        welcomeLabel.font = DynamicFontHelper.defaultHelper.DeviceFontLight
        welcomeLabel.textColor = HistoryPanelUX.WelcomeScreenItemTextColor
        welcomeLabel.numberOfLines = 0
        welcomeLabel.adjustsFontSizeToFitWidth = true

        welcomeLabel.snp.makeConstraints { make in
            make.centerX.equalTo(overlayView)
            // Sets proper top constraint for iPhone 6 in portait and for iPad.
            make.centerY.equalTo(overlayView).offset(HomePanelUX.EmptyTabContentOffset).priority(100)
            // Sets proper top constraint for iPhone 4, 5 in portrait.
            make.top.greaterThanOrEqualTo(overlayView).offset(50)
            make.width.equalTo(HistoryPanelUX.WelcomeScreenItemWidth)
        }
        return overlayView
    }

    override func applyTheme() {
        emptyStateOverlayView.removeFromSuperview()
        emptyStateOverlayView = createEmptyStateOverlayView()
        updateEmptyPanelState()

        super.applyTheme()
    }
}

extension HistoryPanel: UITableViewDataSourcePrefetching {
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        guard !isFetchInProgress, indexPaths.contains(where: shouldLoadRow) else {
            return
        }

        fetchData().uponQueue(.main) { result in
            if let sites = result.successValue {
                let indexPaths: [IndexPath] = sites.compactMap({ site in
                    guard let site = site, let latestVisit = site.latestVisit else {
                        return nil
                    }

                    let indexPath = self.groupedSites.add(site, timestamp: TimeInterval.fromMicrosecondTimestamp(latestVisit.date))
                    return IndexPath(row: indexPath.row, section: indexPath.section + 1)
                })

                self.tableView.insertRows(at: indexPaths, with: .automatic)
            }
        }
    }

    func shouldLoadRow(for indexPath: IndexPath) -> Bool {
        guard indexPath.section > Section.syncAndRecentlyClosed.rawValue else {
            return false
        }

        return indexPath.row >= groupedSites.numberOfItemsForSection(indexPath.section - 1) - 1
    }
}

extension HistoryPanel: HomePanelContextMenu {
    func presentContextMenu(for site: Site, with indexPath: IndexPath, completionHandler: @escaping () -> PhotonActionSheet?) {
        guard let contextMenu = completionHandler() else { return }
        present(contextMenu, animated: true, completion: nil)
    }

    func getSiteDetails(for indexPath: IndexPath) -> Site? {
        return siteForIndexPath(indexPath)
    }

    func getContextMenuActions(for site: Site, with indexPath: IndexPath) -> [PhotonActionSheetItem]? {
        guard var actions = getDefaultContextMenuActions(for: site, homePanelDelegate: homePanelDelegate) else { return nil }

        let removeAction = PhotonActionSheetItem(title: Strings.DeleteFromHistoryContextMenuTitle, iconString: "action_delete", handler: { action in
            self.removeHistoryForURLAtIndexPath(indexPath: indexPath)
        })

        let pinTopSite = PhotonActionSheetItem(title: Strings.PinTopsiteActionTitle, iconString: "action_pin", handler: { action in
            self.pinToTopSites(site)
        })
        actions.append(pinTopSite)
        actions.append(removeAction)
        return actions
    }
}

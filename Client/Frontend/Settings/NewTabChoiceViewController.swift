/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

/// Screen presented to the user when selecting the page that is displayed when the user goes to a new tab.
class NewTabChoiceViewController: ThemedTableViewController {

    let newTabOptions: [NewTabPage] = [.blankPage, .topSites, .bookmarks, .history, .homePage]

    let prefs: Prefs
    var currentChoice: NewTabPage!
    var hasHomePage: Bool!

    fileprivate var authenticationInfo: AuthenticationKeychainInfo?

    init(prefs: Prefs) {
        self.prefs = prefs
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Strings.SettingsNewTabTitle

        tableView.accessibilityIdentifier = "NewTabPage.Setting.Options"

        let headerFooterFrame = CGRect(width: self.view.frame.width, height: SettingsUX.TableViewHeaderFooterHeight)
        let headerView = ThemedTableSectionHeaderFooterView(frame: headerFooterFrame)
        headerView.showTopBorder = false
        headerView.showBottomBorder = true

        let footerView = ThemedTableSectionHeaderFooterView(frame: headerFooterFrame)
        footerView.showTopBorder = true
        footerView.showBottomBorder = false

        tableView.tableHeaderView = headerView
        tableView.tableFooterView = footerView
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.currentChoice = NewTabAccessors.getNewTabPage(prefs)
        self.hasHomePage = HomePageAccessors.getHomePage(prefs) != nil
        tableView.reloadData()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.prefs.setString(currentChoice.rawValue, forKey: NewTabAccessors.PrefKey)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = ThemedTableViewCell()

        let option = newTabOptions[indexPath.row]
        let enabled = (option != .homePage) || hasHomePage

        cell.accessoryType = (currentChoice == option) ? .checkmark : .none
        cell.textLabel?.attributedText = NSAttributedString.tableRowTitle(option.settingTitle, enabled: enabled)
        cell.isUserInteractionEnabled = enabled
        cell.accessibilityIdentifier = option.rawValue
        return cell
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return newTabOptions.count
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        currentChoice = newTabOptions[indexPath.row]
        tableView.reloadData()
    }
}

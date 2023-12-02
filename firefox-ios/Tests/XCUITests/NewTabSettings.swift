// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest

let websiteUrl = "www.mozilla.org"
class NewTabSettingsTest: BaseTestCase {
    // https://testrail.stage.mozaws.net/index.php?/cases/view/2307026
    // Smoketest
    func testCheckNewTabSettingsByDefault() {
        mozWaitForElementToExist(app.buttons[AccessibilityIdentifiers.Toolbar.settingsMenuButton], timeout: 5)
        navigator.nowAt(NewTabScreen)
        navigator.goto(NewTabSettings)
        mozWaitForElementToExist(app.navigationBars["New Tab"])
        XCTAssertTrue(app.tables.cells["Firefox Home"].exists)
        XCTAssertTrue(app.tables.cells["Blank Page"].exists)
        XCTAssertTrue(app.tables.cells["NewTabAsCustomURL"].exists)
    }

    // https://testrail.stage.mozaws.net/index.php?/cases/view/2307027
    // Smoketest
    func testChangeNewTabSettingsShowBlankPage() {
        mozWaitForElementToExist(app.buttons[AccessibilityIdentifiers.Toolbar.settingsMenuButton], timeout: 5)
        navigator.nowAt(NewTabScreen)
        navigator.goto(NewTabSettings)
        mozWaitForElementToExist(app.navigationBars["New Tab"])

        navigator.performAction(Action.SelectNewTabAsBlankPage)
        navigator.performAction(Action.OpenNewTabFromTabTray)

        let addressBar = app.textFields["address"]
        XCTAssertTrue(addressBar.value(forKey: "hasKeyboardFocus") as? Bool ?? false)
        let keyboardCount = app.keyboards.count
        XCTAssert(keyboardCount > 0, "The keyboard is not shown")
        mozWaitForElementToNotExist(app.cells[AccessibilityIdentifiers.FirefoxHomepage.TopSites.itemCell])
        mozWaitForElementToNotExist(app.collectionViews.cells.staticTexts["YouTube"])
        mozWaitForElementToNotExist(app.staticTexts["Highlights"])
    }

    // https://testrail.stage.mozaws.net/index.php?/cases/view/2307028
    func testChangeNewTabSettingsShowFirefoxHome() {
        // Set to history page first since FF Home is default
        waitForTabsButton()
        navigator.nowAt(NewTabScreen)
        navigator.performAction(Action.SelectNewTabAsBlankPage)
        navigator.performAction(Action.OpenNewTabFromTabTray)
        mozWaitForElementToExist(app.buttons["urlBar-cancel"], timeout: TIMEOUT)
        navigator.performAction(Action.CloseURLBarOpen)
        navigator.nowAt(NewTabScreen)
        mozWaitForElementToNotExist(app.collectionViews.cells[AccessibilityIdentifiers.FirefoxHomepage.TopSites.itemCell])

        // Now check if it switches to FF Home
        navigator.goto(SettingsScreen)
        navigator.goto(NewTabSettings)
        navigator.performAction(Action.SelectNewTabAsFirefoxHomePage)
        navigator.performAction(Action.OpenNewTabFromTabTray)
        mozWaitForElementToExist(app.collectionViews.cells[AccessibilityIdentifiers.FirefoxHomepage.TopSites.itemCell])
    }

    // https://testrail.stage.mozaws.net/index.php?/cases/view/2307029
    // Smoketest
    func testChangeNewTabSettingsShowCustomURL() {
        navigator.nowAt(NewTabScreen)
        navigator.goto(NewTabSettings)
        mozWaitForElementToExist(app.navigationBars["New Tab"])
        // Check the placeholder value
        let placeholderValue = app.textFields["NewTabAsCustomURLTextField"].value as! String
        XCTAssertEqual(placeholderValue, "Custom URL")
        navigator.performAction(Action.SelectNewTabAsCustomURL)
        // Check the value typed
        app.textFields["NewTabAsCustomURLTextField"].typeText("mozilla.org")
        let valueTyped = app.textFields["NewTabAsCustomURLTextField"].value as! String
        mozWaitForValueContains(app.textFields["NewTabAsCustomURLTextField"], value: "mozilla")
        XCTAssertEqual(valueTyped, "mozilla.org")
        // Open new page and check that the custom url is used
        navigator.performAction(Action.OpenNewTabFromTabTray)

        navigator.nowAt(NewTabScreen)
        // Check that website is open
        mozWaitForElementToExist(app.webViews.firstMatch, timeout: 20)
        mozWaitForValueContains(app.textFields["url"], value: "mozilla")
    }

    // https://testrail.stage.mozaws.net/index.php?/cases/view/2307030
    func testChangeNewTabSettingsLabel() {
        navigator.nowAt(NewTabScreen)
        // Go to New Tab settings and select Custom URL option
        navigator.performAction(Action.SelectNewTabAsCustomURL)
        navigator.nowAt(NewTabSettings)
        // Enter a custom URL
        app.textFields["NewTabAsCustomURLTextField"].typeText(websiteUrl)
        mozWaitForValueContains(app.textFields["NewTabAsCustomURLTextField"], value: "mozilla")
        navigator.goto(SettingsScreen)
        // Assert that the label showing up in Settings is equal to Custom
        XCTAssertEqual(app.tables.cells["NewTab"].label, "New Tab, Custom")
        // Switch to Blank page and check label
        navigator.performAction(Action.SelectNewTabAsBlankPage)
        navigator.nowAt(NewTabSettings)
        navigator.goto(SettingsScreen)
        XCTAssertEqual(app.tables.cells["NewTab"].label, "New Tab, Blank Page")
        // Switch to FXHome and check label
        navigator.performAction(Action.SelectNewTabAsFirefoxHomePage)
        navigator.nowAt(NewTabSettings)
        navigator.goto(SettingsScreen)
        XCTAssertEqual(app.tables.cells["NewTab"].label, "New Tab, Firefox Home")
    }
}

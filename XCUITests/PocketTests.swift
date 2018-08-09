/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import XCTest

class PocketTest: BaseTestCase {

    func testPocketEnabledByDefault() {
        navigator.goto(NewTabScreen)
        waitforExistence(app.staticTexts["Recommended by Pocket"])

        // There should be two stories on iPhone and three on iPad
        let numPocketStories = app.collectionViews.containing(.cell, identifier:"TopSitesCell").children(matching: .cell).count-1
        if iPad() {
            XCTAssertEqual(numPocketStories, 3)
        } else {
            XCTAssertEqual(numPocketStories, 2)
        }
        // Tap on the first Pocket element
        app.collectionViews.containing(.cell, identifier:"TopSitesCell").children(matching: .cell).element(boundBy: 1).tap()
        waitUntilPageLoad()
        // The url textField is not empty
        XCTAssertNotEqual(app.textFields["url"].value as! String, "", "The url textField is empty")
    }

    func testDisablePocket() {
        navigator.performAction(Action.TogglePocketInNewTab)
        navigator.goto(NewTabScreen)
        waitforNoExistence(app.staticTexts["Recommended by Pocket"])
        // Enable it again
        navigator.performAction(Action.TogglePocketInNewTab)
        navigator.goto(NewTabScreen)
        waitforExistence(app.staticTexts["Recommended by Pocket"])
    }

    func testTapOnMore() {
        // Tap on More should show Pocket website
        navigator.goto(NewTabScreen)
        app.buttons["More"].tap()
        waitUntilPageLoad()
        waitForValueContains(app.textFields["url"], value: "getpocket")
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

class PasswordManagerSetting: Setting {
    private weak var settingsDelegate: PrivacySettingsDelegate?

    override var accessoryView: UIImageView? {
        return SettingDisclosureUtility.buildDisclosureIndicator(theme: theme)
    }

    override var accessibilityIdentifier: String? {
        return AccessibilityIdentifiers.Settings.Logins.title
    }

    init(settings: SettingsTableViewController,
         settingsDelegate: PrivacySettingsDelegate?) {
        self.settingsDelegate = settingsDelegate

        super.init(
            title: NSAttributedString(
                string: .Settings.Passwords.Title,
                attributes: [NSAttributedString.Key.foregroundColor: settings.themeManager.currentTheme.colors.textPrimary]
            )
        )
    }

    override func onClick(_: UINavigationController?) {
        settingsDelegate?.pressedPasswords()
        TelemetryWrapper.recordEvent(category: .action, method: .open, object: .settingsMenuPasswords)
    }
}

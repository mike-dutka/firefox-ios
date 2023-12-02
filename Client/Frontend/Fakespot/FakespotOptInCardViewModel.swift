// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import UIKit
import Common
import Shared
import ComponentLibrary

struct FakespotOptInCardViewModel {
    private struct UX {
        static let contentStackViewPadding: CGFloat = 16
        static let bodyLabelFontSize: CGFloat = 15
    }

    private let tabManager: TabManager
    private let prefs: Prefs
    let cardA11yId: String = AccessibilityIdentifiers.Shopping.OptInCard.card
    var productSitename: String?

    // MARK: Labels
    let headerTitle: String = .Shopping.OptInCardHeaderTitle
    let headerA11yId: String = AccessibilityIdentifiers.Shopping.OptInCard.headerTitle
    let bodyFirstParagraph: String = .Shopping.OptInCardFirstParagraph
    let bodySecondParagraph = String.localizedStringWithFormat(.Shopping.OptInCardSecondParagraph,
                                                               FakespotName.shortName.rawValue,
                                                               MozillaName.shortName.rawValue)
    let bodyA11yId: String = AccessibilityIdentifiers.Shopping.OptInCard.optInCopy
    let disclaimer = String.localizedStringWithFormat(.Shopping.OptInCardDisclaimerText,
                                                      FakespotName.shortName.rawValue)
    let disclaimerLabelA11yId: String = AccessibilityIdentifiers.Shopping.OptInCard.disclaimerText

    // MARK: Buttons
    let learnMoreButtonText: String = .Shopping.OptInCardLearnMoreButtonTitle
    let learnMoreButtonA11yId: String = AccessibilityIdentifiers.Shopping.OptInCard.learnMoreButton
    let termsOfUseButtonText: String = .Shopping.OptInCardTermsOfUse
    let termsOfUseButtonA11yId: String = AccessibilityIdentifiers.Shopping.OptInCard.termsOfUseButton
    let privacyPolicyButtonText: String = .Shopping.OptInCardPrivacyPolicy
    let privacyPolicyButtonA11yId: String = AccessibilityIdentifiers.Shopping.OptInCard.privacyPolicyButton
    let mainButtonText: String = .Shopping.OptInCardMainButtonTitle
    let mainButtonA11yId: String = AccessibilityIdentifiers.Shopping.OptInCard.mainButton
    let secondaryButtonText: String = .Shopping.OptInCardSecondaryButtonTitle
    let secondaryButtonA11yId: String = AccessibilityIdentifiers.Shopping.OptInCard.secondaryButton

    // MARK: Button Actions
    var dismissViewController: ((TelemetryWrapper.EventExtraKey.Shopping?) -> Void)?
    var onOptIn: (() -> Void)?

    // MARK: Links
    let fakespotPrivacyPolicyLink = FakespotUtils.privacyPolicyUrl
    let fakespotTermsOfUseLink = FakespotUtils.termsOfUseUrl
    let fakespotLearnMoreLink = FakespotUtils.learnMoreUrl

    // MARK: Init
    init(profile: Profile = AppContainer.shared.resolve(),
         tabManager: TabManager = AppContainer.shared.resolve()) {
        self.tabManager = tabManager
        prefs = profile.prefs

        prefs.setBool(true, forKey: PrefsKeys.Shopping2023OptInSeen)
        FakespotUtils().addSettingTelemetry()
    }

    // MARK: Actions
    func onTapLearnMore() {
        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .shoppingLearnMoreButton)
        guard let fakespotLearnMoreLink else { return }
        tabManager.addTabsForURLs([fakespotLearnMoreLink], zombie: false, shouldSelectTab: true)
        dismissViewController?(.interactionWithALink)
    }

    func onTapTermsOfUse() {
        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .shoppingTermsOfUseButton)
        guard let fakespotTermsOfUseLink else { return }
        tabManager.addTabsForURLs([fakespotTermsOfUseLink], zombie: false, shouldSelectTab: true)
        dismissViewController?(.interactionWithALink)
    }

    func onTapPrivacyPolicy() {
        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .shoppingPrivacyPolicyButton)
        guard let fakespotPrivacyPolicyLink else { return }
        tabManager.addTabsForURLs([fakespotPrivacyPolicyLink], zombie: false, shouldSelectTab: true)
        dismissViewController?(.interactionWithALink)
    }

    func onTapMainButton() {
        prefs.setBool(true, forKey: PrefsKeys.Shopping2023OptIn)
        prefs.setTimestamp(Date.now(), forKey: PrefsKeys.FakespotLastCFRTimestamp)
        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .shoppingOptIn)
        onOptIn?()
    }

    func onTapSecondaryButton() {
        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .shoppingNotNowButton)
        dismissViewController?(nil)
    }

    var orderWebsites: [String] {
        let currentPartner = PartnerWebsite(for: productSitename?.lowercased()) ?? .amazon
        return currentPartner.orderWebsites
    }

    // MARK: Text methods
    var bodyText: NSAttributedString {
        let websites = orderWebsites
        let font = DefaultDynamicFontHelper.preferredFont(withTextStyle: .body,
                                                          size: UX.bodyLabelFontSize)
        let boldFont = DefaultDynamicFontHelper.preferredBoldFont(withTextStyle: .body,
                                                                  size: UX.bodyLabelFontSize)
        let combinedString = String(format: "%@\n\n%@", bodyFirstParagraph, bodySecondParagraph)

        let plainText = String.localizedStringWithFormat(combinedString,
                                                         websites[0],
                                                         AppName.shortName.rawValue,
                                                         websites[1],
                                                         websites[2])
        let finalString = plainText.attributedText(boldPartsOfString: websites,
                                                   initialFont: font,
                                                   boldFont: boldFont)

        return finalString
    }

    var disclaimerText: NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = UX.contentStackViewPadding
        paragraphStyle.headIndent = UX.contentStackViewPadding
        paragraphStyle.tailIndent = UX.contentStackViewPadding

        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle
        ]

        return NSAttributedString(string: disclaimer, attributes: attributes)
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

public protocol AppEventType: Hashable { }

public enum AppEvent: AppEventType {
    // Events: Startup flow
    case startupFlowComplete

    // Sub-Events for Startup Flow
    case profileInitialized
    case preLaunchDependenciesComplete
    case postLaunchDependenciesComplete
    case accountManagerInitialized

    // Activities: Profile Syncing
    case profileSyncing

    // Activities: Browser
    case browserDidBecomeActive

    // Activites: Tabs
    case tabRestoration
    case selectTab(URL)
}

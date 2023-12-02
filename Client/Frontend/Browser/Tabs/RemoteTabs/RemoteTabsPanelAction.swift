// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import Storage

/// Defines actions sent to Redux for Sync tab in tab tray
enum RemoteTabsPanelAction: Action {
    case panelDidAppear
    case refreshTabs
    case refreshDidBegin
    case refreshDidFail(RemoteTabsPanelEmptyStateReason)
    case cachedTabsAvailable(RemoteTabsPanelCachedResults)
    case refreshDidSucceed([ClientAndTabs])
}

struct RemoteTabsPanelCachedResults {
    let clientAndTabs: [ClientAndTabs]
    let isUpdating: Bool // Whether we are also fetching updates to cached tabs
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Redux
import Common
import Shared

struct TrackingProtectionState: StateType, Equatable, ScreenState {
    let windowUUID: WindowUUID
    var shouldDismiss: Bool
    var showTrackingProtectionSettings: Bool
    var showDetails: Bool
    var showBlockedTrackers: Bool
    var trackingProtectionEnabled: Bool
    var connectionSecure: Bool

    init(appState: AppState,
         uuid: WindowUUID) {
        guard let trackingProtectionState = store.state.screenState(
            TrackingProtectionState.self,
            for: .trackingProtection,
            window: uuid
        ) else {
            self.init(windowUUID: uuid)
            return
        }

        self.init(
            windowUUID: trackingProtectionState.windowUUID,
            shouldDismiss: trackingProtectionState.shouldDismiss,
            showTrackingProtectionSettings: trackingProtectionState.showTrackingProtectionSettings,
            trackingProtectionEnabled: trackingProtectionState.trackingProtectionEnabled,
            connectionSecure: trackingProtectionState.connectionSecure,
            showDetails: trackingProtectionState.showDetails,
            showBlockedTrackers: trackingProtectionState.showBlockedTrackers
        )
    }

    init(
        windowUUID: WindowUUID
    ) {
        self.init(
            windowUUID: windowUUID,
            shouldDismiss: false,
            showTrackingProtectionSettings: false,
            trackingProtectionEnabled: true,
            connectionSecure: true,
            showDetails: false,
            showBlockedTrackers: false
        )
    }

    private init(
        windowUUID: WindowUUID,
        shouldDismiss: Bool,
        showTrackingProtectionSettings: Bool,
        trackingProtectionEnabled: Bool,
        connectionSecure: Bool,
        showDetails: Bool,
        showBlockedTrackers: Bool
    ) {
        self.windowUUID = windowUUID
        self.shouldDismiss = shouldDismiss
        self.showTrackingProtectionSettings = showTrackingProtectionSettings
        self.trackingProtectionEnabled = trackingProtectionEnabled
        self.connectionSecure = connectionSecure
        self.showDetails = showDetails
        self.showBlockedTrackers = showBlockedTrackers
    }

    static let reducer: Reducer<TrackingProtectionState> = { state, action in
        guard action.windowUUID == .unavailable || action.windowUUID == state.windowUUID else { return state }

        switch action.actionType {
        case TrackingProtectionActionType.clearCookiesAndSiteData:
            break
        case TrackingProtectionMiddlewareActionType.navigateToSettings:
            return TrackingProtectionState(
                windowUUID: state.windowUUID,
                shouldDismiss: true,
                showTrackingProtectionSettings: true,
                trackingProtectionEnabled: state.trackingProtectionEnabled,
                connectionSecure: state.connectionSecure,
                showDetails: false,
                showBlockedTrackers: false
            )
        case TrackingProtectionMiddlewareActionType.showTrackingProtectionDetails:
            return TrackingProtectionState(
                windowUUID: state.windowUUID,
                shouldDismiss: false,
                showTrackingProtectionSettings: false,
                trackingProtectionEnabled: state.trackingProtectionEnabled,
                connectionSecure: state.connectionSecure,
                showDetails: true,
                showBlockedTrackers: false
            )
        case TrackingProtectionMiddlewareActionType.showBlockedTrackersDetails:
            return TrackingProtectionState(
                windowUUID: state.windowUUID,
                shouldDismiss: false,
                showTrackingProtectionSettings: false,
                trackingProtectionEnabled: state.trackingProtectionEnabled,
                connectionSecure: state.connectionSecure,
                showDetails: false,
                showBlockedTrackers: true
            )
        case TrackingProtectionMiddlewareActionType.showAlert:
            return TrackingProtectionState(
                windowUUID: state.windowUUID,
                shouldDismiss: false,
                showTrackingProtectionSettings: false,
                trackingProtectionEnabled: state.trackingProtectionEnabled,
                connectionSecure: state.connectionSecure,
                showDetails: false,
                showBlockedTrackers: false
            )
        case TrackingProtectionActionType.toggleTrackingProtectionStatus:
            return TrackingProtectionState(
                windowUUID: state.windowUUID,
                shouldDismiss: false,
                showTrackingProtectionSettings: false,
                trackingProtectionEnabled: !state.trackingProtectionEnabled,
                connectionSecure: state.connectionSecure,
                showDetails: false,
                showBlockedTrackers: false
            )
        case TrackingProtectionMiddlewareActionType.dismissTrackingProtection:
            return TrackingProtectionState(
                windowUUID: state.windowUUID,
                shouldDismiss: true,
                showTrackingProtectionSettings: false,
                trackingProtectionEnabled: state.trackingProtectionEnabled,
                connectionSecure: state.connectionSecure,
                showDetails: false,
                showBlockedTrackers: false
            )
        default:
            return state
        }
        return state
    }
}

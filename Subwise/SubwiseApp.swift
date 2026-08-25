//
//  SubwiseApp.swift
//  Subwise
//
//  Created by Taoufiq on 8/24/26.
//

import SwiftUI
import UIKit

final class SubwiseAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let value = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { try? await KeychainVault.shared.set(value, for: "apnsDeviceToken") }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // The notification settings screen retains local development simulation when APNs is unavailable.
    }
}

@main
struct SubwiseApp: App {
    @UIApplicationDelegateAdaptor(SubwiseAppDelegate.self) private var appDelegate
    init() {
        if ProcessInfo.processInfo.arguments.contains("-uiTestResetOnboarding") {
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        }
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

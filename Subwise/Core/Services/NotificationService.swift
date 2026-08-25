import Foundation
import UIKit
import UserNotifications

actor NotificationService {
    static let shared = NotificationService()
    func requestAuthorization() async throws -> Bool {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        if granted { await MainActor.run { UIApplication.shared.registerForRemoteNotifications() } }
        return granted
    }
    func scheduleRenewal(id: UUID, merchant: String, amount: Money, renewalDate: Date, reminderDays: [Int] = [7, 3, 1]) async throws {
        let center = UNUserNotificationCenter.current()
        for days in reminderDays {
            guard let fireDate = Calendar.current.date(byAdding: .day, value: -days, to: renewalDate), fireDate > .now else { continue }
            let content = UNMutableNotificationContent(); content.title = days == 1 ? "\(merchant) renews tomorrow" : "\(merchant) renews in \(days) days"; content.body = "Expected charge: \(amount.formatted)."; content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour], from: fireDate), repeats: false)
            try await center.add(UNNotificationRequest(identifier: "renewal.\(id).\(days)", content: content, trigger: trigger))
        }
    }
    func cancelRenewal(id: UUID) { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [7, 3, 1].map { "renewal.\(id).\($0)" }) }

    #if DEBUG
    func deliverDevelopmentNotification(title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "development.\(UUID().uuidString)", content: content, trigger: trigger))
    }
    #endif
}

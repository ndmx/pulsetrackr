import FirebaseAuth
import FirebaseMessaging
import FirebaseFunctions
import SwiftUI
import UIKit
import UserNotifications

final class SOSPushRegistration: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    static func requestPermissionAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard FirebaseBootstrap.configureIfAvailable() else { return true }
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token { token, _ in
            if let token { Self.register(token: token) }
        }
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, messaging.apnsToken != nil else { return }
        Self.register(token: fcmToken)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private static func register(token: String) {
        Task {
            do {
                if Auth.auth().currentUser == nil {
                    try await Auth.auth().signInAnonymously()
                }
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
                _ = try await Functions.functions().httpsCallable("register_sos_push_device").call([
                    "fcm_token": token,
                    "app_version": version,
                ])
            } catch {
                // The in-app Firestore alert remains available if push registration fails.
            }
        }
    }
}

import SwiftUI
import UserNotifications

/// Adresse de départ : l'espace organisateur (la page de connexion s'affiche si besoin).
enum AppConfig {
    static let host = "organniversaire.fr"
    static let startURL = URL(string: "https://organniversaire.fr/organizer/dashboard.php")!
    static let userAgentSuffix = "OrgAnniversaireApp/1.0"
    #if DEBUG
    static let pushEnv = "sandbox"
    #else
    static let pushEnv = "production"
    #endif
}

/// État partagé : jeton de notification et page à ouvrir après un appui sur une notification.
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var pushToken: String?
    @Published var pendingURL: URL?
}

@main
struct OrgAnniversaireApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(AppState.shared)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Si l'utilisateur a déjà accepté les notifications, on renouvelle le jeton à chaque lancement
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized {
                DispatchQueue.main.async { application.registerForRemoteNotifications() }
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        DispatchQueue.main.async { AppState.shared.pushToken = token }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Notifications indisponibles : \(error.localizedDescription)")
    }

    // Notification reçue app ouverte : on l'affiche quand même
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    // Appui sur une notification : ouverture de la page indiquée (ex. liste des invités)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let s = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: s), url.host?.hasSuffix(AppConfig.host) == true {
            DispatchQueue.main.async { AppState.shared.pendingURL = url }
        }
        completionHandler()
    }

    static func requestPushPermission(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                if granted { UIApplication.shared.registerForRemoteNotifications() }
                completion?(granted)
            }
        }
    }
}

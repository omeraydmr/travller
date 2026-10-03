import CloudKit
import SwiftUI
import StublyKit
import UIKit
import UserNotifications

@main
struct StublyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = TripStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TripsView()
                .environment(store)
                .environment(\.locale, AppFormat.locale)
                .tint(Color.ink)
                .task {
                    WidgetBridge.shared.tripsChanged(store.trips)
                    await CloudSync.shared.start(with: store)
                    NotificationScheduler.shared.documentsChanged(store.me.passport)
                    NotificationScheduler.shared.tripsChanged(store.trips)
                    LiveActivityController.refresh(trips: store.trips)
                }
                .onOpenURL { url in
                    if let link = TripLink(url: url) {
                        AppRouter.shared.open(link)
                    } else if url.isFileURL {
                        AppRouter.shared.importFile(url)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.flush() }
            if phase == .active {
                Task { await CloudSync.shared.refresh() }
                LiveActivityController.refresh(trips: store.trips)
            }
        }
    }
}

/// iCloud davet bağlantısının uygulamada açılabilmesi için sahne temsilcisi gerekir.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // CloudKit sessiz bildirimleri için (kullanıcıdan izin gerektirmez).
        application.registerForRemoteNotifications()
        return true
    }

    /// Başka bir cihazda yapılan değişiklik: CloudKit sessiz bildirimi.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { return .noData }
        return await CloudSync.shared.handleRemoteNotification() ? .newData : .noData
    }

    /// Uygulama açıkken de bildirimleri göster.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Bildirime dokunuldu: ilgili seyahatin ilgili sekmesini aç.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let link = TripLink(userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run { AppRouter.shared.open(link) }
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in
            await CloudSync.shared.accept(cloudKitShareMetadata)
        }
    }

    /// Widget ve canlı karttan gelen `stubly://` bağlantıları; Wallet, Dosyalar ya da Mail'den paylaşılan
    /// rezervasyon dosyaları (.pkpass, PDF).
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handle(URLContexts)
    }

    /// Uygulama kapalıyken dosya ya da bağlantıyla açıldı.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        handle(connectionOptions.urlContexts)
    }

    private func handle(_ contexts: Set<UIOpenURLContext>) {
        for context in contexts {
            let url = context.url
            Task { @MainActor in
                if let link = TripLink(url: url) {
                    AppRouter.shared.open(link)
                } else if url.isFileURL {
                    AppRouter.shared.importFile(url)
                }
            }
        }
    }
}

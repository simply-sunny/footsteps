import SwiftUI
import SwiftData

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if launchOptions?[.location] != nil {
            // Location wake launch: LocationManager.shared is configured during FootstepsApp.init()
            _ = LocationManager.shared
        }
        return true
    }
}

/// Interim root view for Task 1.
/// In Task 2, this view will be replaced with DailyTrackerView().
struct InterimRootView: View {
    @ObservedObject private var locationManager = LocationManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.walk.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            Text("Footsteps Tracking Active")
                .font(.title2.bold())
            Text("Authorization: \(authStatusDescription)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            if let error = locationManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
    }

    private var authStatusDescription: String {
        switch locationManager.authorizationStatus {
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorizedAlways: return "Authorized Always"
        case .authorizedWhenInUse: return "Authorized When In Use"
        @unknown default: return "Unknown"
        }
    }
}

@main
struct FootstepsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer?
    private let startupError: String?

    init() {
        do {
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let storeDirectory = appSupportURL.appendingPathComponent("FootstepsStore", isDirectory: true)

            try FileManager.default.createDirectory(
                at: storeDirectory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )

            let storeURL = storeDirectory.appendingPathComponent("default.store")
            let schema = Schema([LocationPoint.self])
            let config = ModelConfiguration(
                "FootstepsStore",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let modelContainer = try ModelContainer(for: schema, configurations: [config])

            Self.applyFileProtection(to: storeDirectory)

            self.container = modelContainer
            self.startupError = nil
            LocationManager.shared.configure(modelContainer: modelContainer)
        } catch {
            self.container = nil
            self.startupError = error.localizedDescription
            LocationManager.shared.reportStartupError("ModelContainer initialization failed: \(error.localizedDescription)")
        }
    }

    static func applyFileProtection(to directoryURL: URL) {
        let fileManager = FileManager.default
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directoryURL.path
        )
        if let contents = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) {
            for item in contents {
                try? fileManager.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: item.path
                )
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let startupError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text("Storage Initialization Failed")
                        .font(.title2.bold())
                    Text(startupError)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
            } else if let container {
                // Task 1 interim view. Swapped with DailyTrackerView in Task 2.
                InterimRootView()
                    .modelContainer(container)
            }
        }
    }
}

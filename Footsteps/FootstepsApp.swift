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
            let schema = Schema(versionedSchema: LocationSchemaV2.self)
            let config = ModelConfiguration(
                "FootstepsStore",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: LocationMigrationPlan.self,
                configurations: [config]
            )

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
                DailyTrackerView()
                    .modelContainer(container)
            }
        }
    }
}

import SwiftUI
import LocalAuthentication

@main
struct FusionTelecomsSignoffApp: App {
    @StateObject private var store = WorkOrderStore()
    @StateObject private var lock = AppLockManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(store)
                    .tint(.brandPink)
                    .onOpenURL { url in
                        if let prefill = DeepLinkHandler.parse(url: url) {
                            store.pendingPrefill = prefill
                        }
                    }

                // Covers the app (and the app-switcher snapshot) whenever the
                // lock is on and the app is locked or not frontmost.
                if lock.enabled && (lock.isLocked || scenePhase != .active) {
                    LockScreen()
                        .environmentObject(lock)
                        .transition(.opacity)
                }
            }
            .environmentObject(lock)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                lock.appBecameActive()
                // Don't sync behind the lock screen.
                if !lock.isLocked {
                    Task {
                        await store.syncRemoteJobs()
                        await store.flushPendingCompletions()
                    }
                }
            case .background:
                lock.appEnteredBackground()
            default:
                break
            }
        }
    }
}

/// Optional Face ID / Touch ID / passcode gate. Off by default; enabled from
/// Settings. Locks on cold launch and after the app has been in the background
/// past a short grace period, so the API key and customer data stay protected.
@MainActor
final class AppLockManager: ObservableObject {
    @Published var isLocked: Bool
    @Published private(set) var enabled: Bool

    private var lastBackground: Date?
    private var authenticating = false
    private let graceInterval: TimeInterval = 120 // re-lock after 2 min away

    private static let enabledKey = "AppLockEnabled"

    init() {
        let on = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false
        enabled = on
        isLocked = on // locked on cold launch when enabled
    }

    /// The device's biometry name for UI copy, falling back to "passcode".
    var biometryLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "passcode"
        }
    }

    /// Whether the device can authenticate at all (biometry or a passcode set).
    var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        // Turning it on from inside the app doesn't lock the current session;
        // it takes effect on the next launch / return from background.
        isLocked = false
    }

    func appEnteredBackground() {
        guard enabled else { return }
        lastBackground = Date()
    }

    func appBecameActive() {
        guard enabled else { return }
        if let last = lastBackground, Date().timeIntervalSince(last) >= graceInterval {
            isLocked = true
        }
        if isLocked { authenticate() }
    }

    func authenticate() {
        guard enabled, isLocked, !authenticating else { return }
        authenticating = true
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Field Ops") { success, _ in
            Task { @MainActor in
                self.authenticating = false
                if success { self.isLocked = false }
            }
        }
    }
}

/// Full-screen lock overlay shown while the app is locked.
struct LockScreen: View {
    @EnvironmentObject var lock: AppLockManager

    var body: some View {
        ZStack {
            Color.brandPink.ignoresSafeArea()
            VStack(spacing: 20) {
                LogoBadge(size: 96, corner: 22)
                Text("Field Ops")
                    .font(.title2).fontWeight(.bold)
                    .foregroundStyle(.white)
                if lock.isLocked {
                    Button {
                        lock.authenticate()
                    } label: {
                        Label("Unlock with \(lock.biometryLabel)", systemImage: "lock.fill")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundStyle(Color.brandPink)
                }
            }
        }
        .onAppear { lock.authenticate() }
    }
}

import Foundation
import Combine
import Security
import Network

class WorkOrderStore: ObservableObject {
    /// Pre-filled server URL so technicians don't have to type it. The URL
    /// isn't secret; the API key is (see KeychainStore below).
    static let defaultAPIURL = "https://quote-builder.fusion-telecoms.com"

    @Published var workOrders: [WorkOrder] = []
    @Published var technicianName: String = ""
    @Published var pendingPrefill: JobPrefill?
    @Published var signoffAPIURL: String = ""
    @Published var signoffAPIKey: String = ""
    @Published var isSyncing: Bool = false
    // Set when a manual Provisioning refresh fails, for a one-off alert.
    @Published var refreshErrorMessage: String?
    // Completion reports waiting to reach the server (e.g. a sign-off done with
    // no signal). Flushed on reconnect / foreground.
    @Published var pendingCompletions: [PendingCompletion] = []

    private let ordersKey = "WorkOrders"
    private let techKey = "TechnicianName"
    private let apiURLKey = "SignoffAPIURL"
    private let apiKeyKey = "SignoffAPIKey"
    private let pendingKey = "PendingCompletions"

    private let networkMonitor = NetworkMonitor()
    private var isFlushing = false
    private var lastRegisteredPushToken: String?

    init() {
        load()
        loadPending()
        technicianName = UserDefaults.standard.string(forKey: techKey) ?? ""
        // Server URL: pre-fill the production default on first run, but respect a
        // saved value thereafter (object(forKey:) is nil only before the first save).
        if UserDefaults.standard.object(forKey: apiURLKey) == nil {
            signoffAPIURL = Self.defaultAPIURL
        } else {
            signoffAPIURL = UserDefaults.standard.string(forKey: apiURLKey) ?? ""
        }
        // API key lives in the Keychain so it survives app reinstalls/updates.
        // Migrate a key previously stored in UserDefaults, then scrub the plaintext.
        if let fromKeychain = KeychainStore.read(apiKeyKey) {
            signoffAPIKey = fromKeychain
        } else if let legacy = UserDefaults.standard.string(forKey: apiKeyKey), !legacy.isEmpty {
            signoffAPIKey = legacy
            KeychainStore.write(legacy, for: apiKeyKey)
            UserDefaults.standard.removeObject(forKey: apiKeyKey)
        }

        // Drain the completion queue whenever connectivity returns.
        networkMonitor.onReconnect = { [weak self] in
            Task { await self?.flushPendingCompletions() }
        }
        networkMonitor.start()
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(workOrders) {
            UserDefaults.standard.set(encoded, forKey: ordersKey)
        }
        UserDefaults.standard.set(technicianName, forKey: techKey)
        UserDefaults.standard.set(signoffAPIURL, forKey: apiURLKey)
        // The key is a secret — store it in the Keychain, never UserDefaults.
        KeychainStore.write(signoffAPIKey, for: apiKeyKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: ordersKey),
              let decoded = try? JSONDecoder().decode([WorkOrder].self, from: data)
        else { return }
        workOrders = decoded
    }

    func add(_ workOrder: WorkOrder) {
        workOrders.insert(workOrder, at: 0)
        save()
    }

    func update(_ workOrder: WorkOrder) {
        guard let index = workOrders.firstIndex(where: { $0.id == workOrder.id }) else { return }
        workOrders[index] = workOrder
        save()
    }

    func delete(ids: [UUID]) {
        for id in ids { PhotoStore.deleteAll(for: id) }
        workOrders.removeAll { ids.contains($0.id) }
        save()
    }

    /// Background sync of manually-queued jobs (Send to Sign-off). Runs on
    /// foreground; silent on failure.
    @MainActor
    func syncRemoteJobs() async {
        guard !signoffAPIURL.isEmpty, !signoffAPIKey.isEmpty, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        guard let jobs = try? await SignoffJobsAPI.fetchPending(
            baseURL: signoffAPIURL, apiKey: signoffAPIKey
        ) else { return }
        await mergeAndClaim(jobs)
        // A successful fetch means we're online — a good moment to drain queued
        // completion reports.
        await flushPendingCompletions()
    }

    /// Manual Refresh: pull jobs currently in the CRM's Provisioning stage.
    /// Surfaces an error message so the technician knows if it couldn't run.
    @MainActor
    func refreshProvisioningJobs() async {
        guard !signoffAPIURL.isEmpty, !signoffAPIKey.isEmpty else {
            refreshErrorMessage = "Set your server URL and API key in Settings first."
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let jobs = try await SignoffJobsAPI.fetchProvisioning(baseURL: signoffAPIURL, apiKey: signoffAPIKey)
            await mergeAndClaim(jobs)
        } catch {
            refreshErrorMessage = error.localizedDescription
        }
    }

    /// Insert any jobs not already present (matched by job reference), stamping
    /// the remote job id, and claim each so it isn't re-delivered.
    @MainActor
    private func mergeAndClaim(_ jobs: [RemoteJob]) async {
        var didAdd = false
        for job in jobs {
            guard !workOrders.contains(where: { $0.jobReference == job.jobReference }) else { continue }
            let workOrder = WorkOrder(
                jobReference: job.jobReference,
                customerName: job.customerName,
                customerAddress: job.customerAddress ?? "",
                customerEmail: job.customerEmail ?? "",
                workDescription: job.workDescription ?? "",
                completedDate: Date(),
                technicianName: technicianName,
                remoteJobId: job.id
            )
            workOrders.insert(workOrder, at: 0)
            didAdd = true
            try? await SignoffJobsAPI.claimJob(id: job.id, baseURL: signoffAPIURL, apiKey: signoffAPIKey)
        }
        if didAdd { save() }
    }

    /// Report a Quote Builder job as signed off so the server can mark its CRM
    /// opportunity live. Durable: the report is queued first (survives app kill
    /// and no signal), then an immediate send is attempted; anything still
    /// queued is retried on reconnect / next foreground. No-op for locally
    /// created jobs (no remoteJobId).
    @MainActor
    func reportCompletion(
        for workOrder: WorkOrder,
        goLiveDate: Date,
        installType: InstallType,
        signedByCustomer: Bool
    ) async {
        guard let jobId = workOrder.remoteJobId else { return }
        pendingCompletions.append(PendingCompletion(
            id: UUID(),
            remoteJobId: jobId,
            goLiveDate: SignoffJobsAPI.isoDay(goLiveDate),
            installTypeRaw: installType.rawValue,
            signedByCustomer: signedByCustomer,
            jobReference: workOrder.jobReference,
            queuedAt: Date()
        ))
        persistPending()
        await flushPendingCompletions()
    }

    /// Try to send every queued completion report, removing each as it succeeds.
    /// Stops on the first failure (still offline / server down) and leaves the
    /// rest queued for the next attempt.
    @MainActor
    func flushPendingCompletions() async {
        guard !signoffAPIURL.isEmpty, !signoffAPIKey.isEmpty, !isFlushing else { return }
        guard !pendingCompletions.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        for item in pendingCompletions {
            guard let installType = InstallType(rawValue: item.installTypeRaw) else {
                // Corrupt entry — drop it rather than wedge the queue.
                pendingCompletions.removeAll { $0.id == item.id }
                persistPending()
                continue
            }
            do {
                try await SignoffJobsAPI.completeJob(
                    id: item.remoteJobId,
                    goLiveDate: item.goLiveDate,
                    installType: installType,
                    signedByCustomer: item.signedByCustomer,
                    baseURL: signoffAPIURL,
                    apiKey: signoffAPIKey
                )
                pendingCompletions.removeAll { $0.id == item.id }
                persistPending()
            } catch {
                break // still unreachable — keep the remainder queued
            }
        }
    }

    /// Send this device's APNs token to the server so it can push new-job
    /// alerts. Deduped within a session; the server upsert is idempotent.
    @MainActor
    func registerPushToken(_ token: String) async {
        guard !signoffAPIURL.isEmpty, !signoffAPIKey.isEmpty else { return }
        guard token != lastRegisteredPushToken else { return }
        do {
            try await QuoteBuilderAPI.registerDevice(token: token, baseURL: signoffAPIURL, apiKey: signoffAPIKey)
            lastRegisteredPushToken = token
        } catch {
            // Try again next launch.
        }
    }

    private func loadPending() {
        guard let data = UserDefaults.standard.data(forKey: pendingKey),
              let decoded = try? JSONDecoder().decode([PendingCompletion].self, from: data)
        else { return }
        pendingCompletions = decoded
    }

    private func persistPending() {
        if let data = try? JSONEncoder().encode(pendingCompletions) {
            UserDefaults.standard.set(data, forKey: pendingKey)
        }
    }
}

/// A completion report awaiting delivery to the server.
struct PendingCompletion: Codable, Identifiable {
    let id: UUID
    let remoteJobId: Int
    let goLiveDate: String      // yyyy-MM-dd
    let installTypeRaw: String  // InstallType rawValue
    let signedByCustomer: Bool
    let jobReference: String
    let queuedAt: Date
}

/// Watches connectivity and fires `onReconnect` when the network comes back,
/// so queued completion reports can be flushed promptly.
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "FieldOps.NetworkMonitor")
    private var wasSatisfied = true
    var onReconnect: (() -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied
            if satisfied && !self.wasSatisfied {
                DispatchQueue.main.async { self.onReconnect?() }
            }
            self.wasSatisfied = satisfied
        }
        monitor.start(queue: queue)
    }
}

/// Minimal Keychain wrapper for the one secret this app stores (the sync API
/// key). Generic-password items persist across app reinstalls/updates on a
/// device, so the key only ever has to be entered once.
private enum KeychainStore {
    static func write(_ value: String, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        // Replace any existing item; an empty value just clears it.
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }
}

import Foundation
import Combine
import Security

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

    private let ordersKey = "WorkOrders"
    private let techKey = "TechnicianName"
    private let apiURLKey = "SignoffAPIURL"
    private let apiKeyKey = "SignoffAPIKey"

    init() {
        load()
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
    /// opportunity live. Best-effort: does nothing for locally-created jobs (no
    /// remoteJobId) or when sync isn't configured, and never throws.
    @MainActor
    func reportCompletion(
        for workOrder: WorkOrder,
        goLiveDate: Date,
        installType: InstallType,
        signedByCustomer: Bool
    ) async {
        guard let jobId = workOrder.remoteJobId,
              !signoffAPIURL.isEmpty, !signoffAPIKey.isEmpty else { return }
        try? await SignoffJobsAPI.completeJob(
            id: jobId,
            goLiveDate: SignoffJobsAPI.isoDay(goLiveDate),
            installType: installType,
            signedByCustomer: signedByCustomer,
            baseURL: signoffAPIURL,
            apiKey: signoffAPIKey
        )
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

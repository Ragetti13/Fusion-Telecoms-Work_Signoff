import Foundation
import Combine

class WorkOrderStore: ObservableObject {
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
        signoffAPIURL = UserDefaults.standard.string(forKey: apiURLKey) ?? ""
        signoffAPIKey = UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(workOrders) {
            UserDefaults.standard.set(encoded, forKey: ordersKey)
        }
        UserDefaults.standard.set(technicianName, forKey: techKey)
        UserDefaults.standard.set(signoffAPIURL, forKey: apiURLKey)
        UserDefaults.standard.set(signoffAPIKey, forKey: apiKeyKey)
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

import Foundation
import Combine

class WorkOrderStore: ObservableObject {
    @Published var workOrders: [WorkOrder] = []
    @Published var technicianName: String = ""
    @Published var pendingPrefill: JobPrefill?
    @Published var signoffAPIURL: String = ""
    @Published var signoffAPIKey: String = ""
    @Published var isSyncing: Bool = false

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

    @MainActor
    func syncRemoteJobs() async {
        guard !signoffAPIURL.isEmpty, !signoffAPIKey.isEmpty, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        guard let jobs = try? await SignoffJobsAPI.fetchPending(
            baseURL: signoffAPIURL, apiKey: signoffAPIKey
        ) else { return }

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
                technicianName: technicianName
            )
            workOrders.insert(workOrder, at: 0)
            didAdd = true
            try? await SignoffJobsAPI.claimJob(id: job.id, baseURL: signoffAPIURL, apiKey: signoffAPIKey)
        }

        if didAdd { save() }
    }
}

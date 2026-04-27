import Foundation
import Combine

class WorkOrderStore: ObservableObject {
    @Published var workOrders: [WorkOrder] = []
    @Published var technicianName: String = ""

    private let ordersKey = "WorkOrders"
    private let techKey = "TechnicianName"

    init() {
        load()
        technicianName = UserDefaults.standard.string(forKey: techKey) ?? ""
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(workOrders) {
            UserDefaults.standard.set(encoded, forKey: ordersKey)
        }
        UserDefaults.standard.set(technicianName, forKey: techKey)
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
}

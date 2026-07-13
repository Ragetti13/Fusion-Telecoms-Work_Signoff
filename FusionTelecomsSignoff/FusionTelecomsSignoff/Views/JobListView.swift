import SwiftUI

struct JobListView: View {
    @EnvironmentObject var store: WorkOrderStore
    @State private var showingNewJob = false
    @State private var showingSettings = false

    private var pendingJobs: [WorkOrder] { store.workOrders.filter { !$0.isSigned } }
    private var completedJobs: [WorkOrder] { store.workOrders.filter { $0.isSigned } }

    var body: some View {
        NavigationStack {
            Group {
                if store.workOrders.isEmpty {
                    emptyState
                } else {
                    jobList
                }
            }
            .navigationTitle("Work Sign-Off")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewJob = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewJob, onDismiss: { store.pendingPrefill = nil }) {
                NewJobView(prefill: store.pendingPrefill)
            }
            .onChange(of: store.pendingPrefill != nil) { hasPrefill in
                if hasPrefill { showingNewJob = true }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private var jobList: some View {
        List {
            if !pendingJobs.isEmpty {
                Section("Awaiting Signature") {
                    ForEach(pendingJobs) { job in
                        NavigationLink(destination: SignatureCaptureView(workOrder: job)) {
                            JobRowView(workOrder: job)
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { pendingJobs[$0].id }
                        store.delete(ids: ids)
                    }
                }
            }

            if !completedJobs.isEmpty {
                Section("Signed Off") {
                    ForEach(completedJobs) { job in
                        NavigationLink(destination: CompletedJobDetailView(workOrder: job)) {
                            JobRowView(workOrder: job)
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { completedJobs[$0].id }
                        store.delete(ids: ids)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No Jobs Yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Tap + to create your first work order")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct JobRowView: View {
    let workOrder: WorkOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(workOrder.jobReference.isEmpty ? "No Reference" : workOrder.jobReference)
                    .font(.headline)
                Spacer()
                Image(systemName: workOrder.isSigned ? "checkmark.seal.fill" : "signature")
                    .foregroundStyle(workOrder.isSigned ? .green : .orange)
            }
            Text(workOrder.customerName.isEmpty ? "Unknown Customer" : workOrder.customerName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !workOrder.customerAddress.isEmpty {
                Text(workOrder.customerAddress)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Text(workOrder.completedDate, style: .date)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

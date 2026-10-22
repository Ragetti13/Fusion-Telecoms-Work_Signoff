import SwiftUI

struct JobListView: View {
    @EnvironmentObject var store: WorkOrderStore
    @State private var showingNewJob = false
    @State private var showingSettings = false

    private var pendingJobs: [WorkOrder] { store.workOrders.filter { !$0.isSigned } }
    private var completedJobs: [WorkOrder] { store.workOrders.filter { $0.isSigned } }

    // Split into typed sub-expressions (toolbar, binding, content) so the
    // SwiftUI type-checker doesn't have to infer one large body expression.
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Color.brandPink, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .sheet(isPresented: $showingNewJob, onDismiss: { store.pendingPrefill = nil }) {
                    NewJobView(prefill: store.pendingPrefill)
                }
                .onChange(of: store.pendingPrefill != nil) { hasPrefill in
                    if hasPrefill { showingNewJob = true }
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                }
                .alert("Couldn't refresh", isPresented: showRefreshError) {
                    Button("OK", role: .cancel) { store.refreshErrorMessage = nil }
                } message: {
                    Text(store.refreshErrorMessage ?? "")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.workOrders.isEmpty {
            emptyState
        } else {
            jobList
        }
    }

    private var showRefreshError: Binding<Bool> {
        Binding(
            get: { store.refreshErrorMessage != nil },
            set: { if !$0 { store.refreshErrorMessage = nil } }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            // Left-aligned landscape logo. .original keeps the white wordmark and
            // coloured atom dots (otherwise the bar would tint it flat/invisible).
            Image("LogoLandscape")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(height: 26)
                .accessibilityLabel("Fusion Telecoms")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingSettings = true } label: {
                Image(systemName: "person.circle")
                    .foregroundStyle(.white)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { Task { await store.refreshProvisioningJobs() } } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.white)
            }
            .disabled(store.isSyncing)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingNewJob = true } label: {
                Image(systemName: "plus")
                    .foregroundStyle(.white)
            }
        }
    }

    private var jobList: some View {
        List {
            if !pendingJobs.isEmpty {
                Section {
                    ForEach(pendingJobs) { job in
                        NavigationLink(destination: SignatureCaptureView(workOrder: job)) {
                            JobRowView(workOrder: job)
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { pendingJobs[$0].id }
                        store.delete(ids: ids)
                    }
                } header: {
                    SectionHeader(title: "Awaiting Signature", tint: .brandPink)
                }
            }

            if !completedJobs.isEmpty {
                Section {
                    ForEach(completedJobs) { job in
                        NavigationLink(destination: CompletedJobDetailView(workOrder: job)) {
                            JobRowView(workOrder: job)
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { completedJobs[$0].id }
                        store.delete(ids: ids)
                    }
                } header: {
                    SectionHeader(title: "Signed Off", tint: .green)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.refreshProvisioningJobs() }
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer()
            LogoBadge(size: 108, corner: 24)
            VStack(spacing: 6) {
                Text("Work Sign-Off")
                    .font(.title2).fontWeight(.bold)
                Text("Pull down to load jobs from Quote Builder, or tap + to create one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct SectionHeader: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(title)
                .font(.footnote).fontWeight(.semibold)
                .foregroundStyle(tint)
                .textCase(.uppercase)
        }
    }
}

struct JobRowView: View {
    let workOrder: WorkOrder

    private var signed: Bool { workOrder.isSigned }
    private var accent: Color { signed ? .green : .brandPink }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(accent.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: signed ? "checkmark.seal.fill" : "signature")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(workOrder.jobReference.isEmpty ? "No Reference" : workOrder.jobReference)
                    .font(.headline)
                Text(workOrder.customerName.isEmpty ? "Unknown Customer" : workOrder.customerName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !workOrder.customerAddress.isEmpty {
                    Label(workOrder.customerAddress, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Label(workOrder.completedDate.formatted(date: .abbreviated, time: .omitted),
                      systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}

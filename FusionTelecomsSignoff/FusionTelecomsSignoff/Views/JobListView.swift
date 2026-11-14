import SwiftUI

struct JobListView: View {
    @EnvironmentObject var store: WorkOrderStore
    @State private var showingNewJob = false
    @State private var showingSettings = false
    @State private var pendingDeletion: PendingDeletion?

    /// A swipe-to-delete waiting on confirmation. Deleting a signed job is
    /// irreversible in a way worth spelling out: the signature image and the
    /// install photos live only on this device — nothing uploads them — so the
    /// swipe destroys the only copy of what the customer actually signed.
    private struct PendingDeletion: Identifiable {
        let id = UUID()
        let ids: [UUID]
        let signed: Bool
    }

    private var pendingJobs: [WorkOrder] { store.workOrders.filter { !$0.isSigned } }
    private var completedJobs: [WorkOrder] { store.workOrders.filter { $0.isSigned } }

    // Split into typed sub-expressions (toolbar, binding, content) so the
    // SwiftUI type-checker doesn't have to infer one large body expression.
    var body: some View {
        NavigationStack {
            content
                // A real title, not "": the back button on a pushed screen
                // takes its label from here, and VoiceOver had no name for
                // this screen at all. The logo still carries the branding.
                .navigationTitle("Jobs")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Color.brandPink, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .sheet(isPresented: $showingNewJob, onDismiss: { store.pendingPrefill = nil }) {
                    NewJobView(prefill: store.pendingPrefill)
                }
                .onChange(of: store.pendingPrefill != nil) { _, hasPrefill in
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
                // Sign-off success already buzzes; failure was silent. A
                // technician holding the phone one-handed on a ladder feels
                // this before reading it.
                .sensoryFeedback(.error, trigger: store.refreshErrorMessage) { _, new in
                    new != nil
                }
                .confirmationDialog(
                    deletionTitle,
                    isPresented: deletionConfirmation,
                    titleVisibility: .visible,
                    presenting: pendingDeletion
                ) { deletion in
                    Button(deletion.signed ? "Delete Sign-Off" : "Delete Job", role: .destructive) {
                        store.delete(ids: deletion.ids)
                        pendingDeletion = nil
                    }
                } message: { deletion in
                    Text(deletion.signed
                         ? "The signature and install photos are kept only on this iPhone, so this deletes the only copy of what the customer signed. Email the PDF first if you need the record."
                         : "This removes the job from this iPhone. You can load it again from Quote Builder.")
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

    private var deletionConfirmation: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    /// Typed as String deliberately: a bare ternary of two string literals
    /// leaves the compiler choosing between the LocalizedStringKey and
    /// StringProtocol overloads of confirmationDialog.
    private var deletionTitle: String {
        pendingDeletion?.signed == true ? "Delete this sign-off?" : "Delete this job?"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        BrandLogoLeading()
        ToolbarItem(placement: .topBarTrailing) {
            Button { Task { await store.refreshProvisioningJobs() } } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.white)
            }
            .disabled(store.isSyncing)
            .accessibilityLabel("Refresh jobs")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingNewJob = true } label: {
                Image(systemName: "plus")
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("New job")
        }
        // Was a Menu containing a single Settings item, which cost an extra tap
        // for nothing; it opens Settings directly now.
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Settings")
        }
    }

    private var jobList: some View {
        List {
            if !store.pendingCompletions.isEmpty {
                Section {
                    pendingSyncBanner
                }
            }

            if !pendingJobs.isEmpty {
                Section {
                    ForEach(pendingJobs) { job in
                        NavigationLink(destination: SignatureCaptureView(workOrder: job)) {
                            JobRowView(workOrder: job)
                        }
                    }
                    .onDelete { offsets in
                        pendingDeletion = PendingDeletion(
                            ids: offsets.map { pendingJobs[$0].id }, signed: false
                        )
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
                        pendingDeletion = PendingDeletion(
                            ids: offsets.map { completedJobs[$0].id }, signed: true
                        )
                    }
                } header: {
                    SectionHeader(title: "Signed Off", tint: .green)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.refreshProvisioningJobs() }
    }

    private var pendingSyncBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                .font(.title3)
                .foregroundStyle(Color.brandPink)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.pendingCompletions.count) \(store.pendingCompletions.count == 1 ? "sign-off" : "sign-offs") waiting to sync")
                    .font(.subheadline).fontWeight(.semibold)
                Text("Sent to the CRM automatically when you're back online.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Retry") { Task { await store.flushPendingCompletions() } }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
                .tint(.brandPink)
        }
        .padding(.vertical, 4)
    }

    /// Wrapped in a ScrollView so `refreshable` has something to pull. It used
    /// to be a bare VStack that told the technician to "pull down to load
    /// jobs" — on the very first screen of a fresh install, where there was
    /// nothing scrollable and so nothing to pull. The button does the same job
    /// without relying on a hidden gesture at all.
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 22) {
                LogoBadge(size: 108, corner: Layout.radiusBadge)
                VStack(spacing: 6) {
                    Text("No jobs yet")
                        .font(.title2).fontWeight(.bold)
                    Text("Load the jobs waiting in Quote Builder, or tap + to add one by hand.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                Button {
                    Task { await store.refreshProvisioningJobs() }
                } label: {
                    Label("Load Jobs from Quote Builder", systemImage: "arrow.clockwise")
                }
                .brandPrimaryButton()
                .disabled(store.isSyncing)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .containerRelativeFrame(.vertical)
        }
        .refreshable { await store.refreshProvisioningJobs() }
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

    /// The badge grows with the text beside it. At an accessibility text size a
    /// fixed 44pt tile next to scaled-up labels looked like a mistake.
    @ScaledMetric(relativeTo: .headline) private var tile: CGFloat = 44

    private var signed: Bool { workOrder.isSigned }
    private var accent: Color { signed ? .green : .brandPink }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(accent.opacity(0.12))
                    .frame(width: tile, height: tile)
                Image(systemName: signed ? "checkmark.seal.fill" : "signature")
                    .font(.headline.weight(.semibold))
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
        // One VoiceOver utterance for the row instead of four separate stops.
        .accessibilityElement(children: .combine)
    }
}

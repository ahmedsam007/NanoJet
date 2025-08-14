import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DownloadEngine
import Combine

private struct ReportWrapper: Identifiable {
    let id = UUID()
    let value: TestReport
}

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appModel: AppViewModel
    @State private var inputURL: String = ""
    @State private var expandedItemIds: Set<UUID> = []
    @State private var selectedItemIds: Set<UUID> = []
    @State private var historyFilter: HistoryFilter = .all
    @State private var sortKey: SortKey = .nameAZ

    var body: some View {
        VStack(spacing: 8) {
            if let err = appModel.shutdownError {
                HStack(spacing: 8) {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Open Privacy Settings") { appModel.openAutomationPrivacyPane() }
                        .buttonStyle(.bordered)
                    Button("Retry") { appModel.shutdownNow() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .transition(.opacity)
            }
            if appModel.isShutdownCountdownActive {
                HStack(spacing: 8) {
                    Label("Shutting down in \(appModel.shutdownCountdownRemaining)s", systemImage: "power")
                        .foregroundStyle(.red)
                        .font(.headline)
                    Spacer()
                    Button("Cancel") { appModel.cancelShutdownCountdown() }
                        .buttonStyle(.bordered)
                    Button("Shut Down Now") { appModel.shutdownNow() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Button(action: {
                        // Keep quick status check
                        appModel.testConnection()
                        // Open dedicated Test Connection window/tab
                        let def = URL(string: "https://clients3.google.com/generate_204")!
                        openWindow(id: "test-connection", value: def)
                    }) {
                        if appModel.connectionStatus == .checking {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .keyboardShortcut("t", modifiers: [.command])
                    Group {
                        switch appModel.connectionStatus {
                        case .idle:
                            EmptyView()
                        case .checking:
                            Text("Checking…")
                                .foregroundStyle(.secondary)
                        case .online:
                            Label("Online", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        case .offline:
                            Label("Offline", systemImage: "xmark.seal.fill").foregroundStyle(.red)
                        }
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
            }

            VStack(spacing: 0) {
                // Main status filter + actions
                HStack(spacing: 8) {
                    Text("Downloads")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $historyFilter) {
                        ForEach(HistoryFilter.allCases) { f in
                            let count = appModel.items.filter { f.includes($0.status) }.count
                            Text(count > 0 ? "\(f.title) (\(count))" : f.title)
                                .tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 360)

                    Spacer()
                    // Sort control (Type, Size, Older, Status, A–Z, Z–A)
                    Menu {
                        Picker("Sort", selection: $sortKey) {
                            Text("Type").tag(SortKey.type)
                            Text("Size").tag(SortKey.size)
                            Text("Older").tag(SortKey.older)
                            Text("Status").tag(SortKey.status)
                            Text("A–Z").tag(SortKey.nameAZ)
                            Text("Z–A").tag(SortKey.nameZA)
                        }
                    } label: {
                        Label("Sort: \(sortKey.title)", systemImage: "arrow.up.arrow.down")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.mini)
                    .fixedSize()
                    Button(role: .destructive) {
                        appModel.clearHistory()
                    } label: {
                        Label("Clear Finished", systemImage: "trash")
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                Divider()

                let filteredItems = appModel.items.filter { historyFilter.includes($0.status) }
                let sortedItems = filteredItems.sorted { a, b in
                    switch sortKey {
                    case .type:
                        let ta = typeKey(for: a)
                        let tb = typeKey(for: b)
                        if ta == tb { return nameAsc(a, b) }
                        return ta < tb
                    case .size:
                        let sa = sizeValue(for: a)
                        let sb = sizeValue(for: b)
                        if sa == sb { return nameAsc(a, b) }
                        return sa > sb // Largest first
                    case .older:
                        if a.createdAt == b.createdAt { return nameAsc(a, b) }
                        return a.createdAt < b.createdAt // Older first
                    case .status:
                        let ra = a.status.rawValue
                        let rb = b.status.rawValue
                        if ra == rb { return nameAsc(a, b) }
                        return ra < rb
                    case .nameAZ:
                        return nameAsc(a, b)
                    case .nameZA:
                        return !nameAsc(a, b)
                    }
                }
                // Update header with proper IDs now that we have sortedItems
                DownloadsHeaderRow(allItemIds: sortedItems.map { $0.id }, selectedIds: $selectedItemIds)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                Divider()

                if filteredItems.isEmpty {
                    VStack {
                        EmptyStateCard(
                            systemImage: historyFilter == .active ? "bolt.fill" : "tray",
                            title: historyFilter == .all ? "No downloads yet" : (historyFilter == .active ? "No active downloads" : "No items in this filter"),
                            message: historyFilter == .all ? "Add a URL above to start downloading. Active and finished items will appear here." : (historyFilter == .active ? "Start a download to see it listed here while in progress." : "Try switching filters or start a new download.")
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    List {
                        ForEach(sortedItems) { item in
                            DownloadRow(
                                item: item,
                                isSelected: Binding(
                                    get: { selectedItemIds.contains(item.id) },
                                    set: { newValue in
                                        if newValue { selectedItemIds.insert(item.id) } else { selectedItemIds.remove(item.id) }
                                    }
                                ),
                                isExpanded: Binding(
                                    get: { expandedItemIds.contains(item.id) },
                                    set: { newValue in
                                        if newValue { expandedItemIds.insert(item.id) } else { expandedItemIds.remove(item.id) }
                                    }
                                )
                            )
                            .environmentObject(appModel)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .padding(.vertical, 4)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                }
            }
            .glassCard()
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.controlSize, .small)
        }
        .frame(minWidth: 680, minHeight: 500)
        
        .toolbar {
            ToolbarItem(placement: .principal) {
                TextField("Paste URL to download", text: $inputURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 360, idealWidth: 420, maxWidth: 520)
                    .onSubmit {
                        appModel.enqueue(urlString: inputURL)
                        inputURL = ""
                    }
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $appModel.shutdownWhenDone) {
                    HStack(spacing: 6) {
                        Image(systemName: "power")
                            .symbolVariant(.fill)
                        Text("Shut down when done")
                            .font(.caption)
                    }
                }
                .toggleStyle(iOS26SwitchStyle())
                .help("Automatically shut down the Mac after all downloads finish")
            }
        }
    }
}

// MARK: - Glass styling
private struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

private extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
}

// MARK: - iOS 26-like switch style (compact, green when ON)
private struct iOS26SwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            HStack(spacing: 8) {
                configuration.label
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(configuration.isOn ? Color.green.opacity(0.9) : Color.secondary.opacity(0.25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .frame(width: 46, height: 24)
                        .shadow(color: configuration.isOn ? Color.green.opacity(0.25) : .clear, radius: 8, x: 0, y: 2)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        .padding(2)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isOn)
    }
}

// MARK: - Empty State Card (Liquid Glass style)
private struct EmptyStateCard: View {
    let systemImage: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 84, height: 84)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
private enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, active, completed, failed, canceled, deleted
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .active: return "Active"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .canceled: return "Canceled"
        case .deleted: return "Deleted"
        }
    }
    func includes(_ status: DownloadStatus) -> Bool {
        switch self {
        case .all: return true
        case .active: return ![.completed, .failed, .canceled].contains(status)
        case .completed: return status == .completed
        case .failed: return status == .failed
        case .canceled: return status == .canceled
        case .deleted: return status == .deleted
        }
    }
}
// MARK: - Download list (header + row)

private struct DownloadColumns {
    static let size: CGFloat = 120
    static let status: CGFloat = 120
    static let resumable: CGFloat = 85
    static let progress: CGFloat = 120
    static let chunks: CGFloat = 160
    static let speed: CGFloat = 55
    static let eta: CGFloat = 45
    static let actions: CGFloat = 180
}

private struct DownloadsHeaderRow: View {
    let allItemIds: [UUID]
    @Binding var selectedIds: Set<UUID>
    var body: some View {
        HStack(spacing: 8) {
            // Selection
            Toggle(isOn: Binding(
                get: { !allItemIds.isEmpty && selectedIds.count == allItemIds.count },
                set: { newValue in
                    if newValue { selectedIds = Set(allItemIds) } else { selectedIds.removeAll() }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 18)
            // File (flex)
            Text("File")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
            // Size
            Text("Size")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: DownloadColumns.size, alignment: .leading)
            // Status
            Text("Status")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: DownloadColumns.status, alignment: .leading)
            // Resumable
            Text("Resumable")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: DownloadColumns.resumable, alignment: .leading)
            // Progress
            Text("Progress")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: DownloadColumns.progress, alignment: .leading)
            // Chunks
            Text("Chunks")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: DownloadColumns.chunks, alignment: .leading)
            // Speed
            Text("Speed")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: DownloadColumns.speed, alignment: .leading)
            // ETA
            Text("ETA")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: DownloadColumns.eta, alignment: .leading)
            // Actions
            Text("Actions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: DownloadColumns.actions, alignment: .trailing)
        }
    }
}

private struct DownloadRow: View {
    let item: DownloadItem
    @Binding var isSelected: Bool
    @Binding var isExpanded: Bool
    @EnvironmentObject private var appModel: AppViewModel
    @State private var isHovering: Bool = false

    var body: some View {
                    VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle(isOn: $isSelected) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .frame(width: 18)
                // File (flex)
                        HStack(spacing: 8) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Image(nsImage: fileIcon(for: item))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                                .cornerRadius(4)
                            Text(item.finalFileName ?? item.url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                        }
                .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)

                // Size
                    Group {
                        if item.status == .downloading {
                            if let total = item.totalBytes, total > 0 {
                                Text(bytesPairMBMixed(received: item.receivedBytes, total: total))
                            } else {
                                Text("\(formatBytesMB3(item.receivedBytes))")
                            }
                        } else {
                        if let total = item.totalBytes, total > 0 {
                            Text(bytesPair(received: item.receivedBytes, total: total))
                        } else {
                            Text("\(formatBytes(item.receivedBytes))")
                            }
                        }
                    }
                    .font(.caption)
                .frame(width: DownloadColumns.size, alignment: .leading)
                
                // Status
                    let (icon, color, text) = statusPresentation(for: item.status)
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .imageScale(.small)
                            .foregroundStyle(color)
                        Text(text)
                            .font(.caption)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                .frame(width: DownloadColumns.status, alignment: .leading)

                // Resumable (Yes/No)
                Text(item.supportsRanges ? "Yes" : "No")
                    .font(.caption)
                    .foregroundStyle(item.supportsRanges ? .green : .secondary)
                    .frame(width: DownloadColumns.resumable, alignment: .leading)

                // Progress
                Group {
                    if (item.status == .downloading || item.status == .paused), let total = item.totalBytes, total > 0 {
                        HStack(spacing: 6) {
                            ProgressView(value: Double(item.receivedBytes), total: Double(total))
                                .controlSize(.small)
                                .frame(width: 90)
                            Text(formatPercent(received: min(item.receivedBytes, total), total: total))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if (item.status == .downloading || item.status == .paused) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 100)
                    } else {
                        Text("—")
                    }
                }
                .frame(width: DownloadColumns.progress, alignment: .leading)

                // Chunks
                    ChunkMiniBar(segments: item.segments ?? [])
                    .frame(width: DownloadColumns.chunks, height: 12, alignment: .leading)

                // Speed
                Text(formatSpeedCompact(item.speedBytesPerSec))
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: DownloadColumns.speed, alignment: .leading)

                // ETA
                Group {
                    if let eta = item.etaSeconds, eta > 0 { Text(formatETACompact(eta)) } else { Text("—") }
                }
                .font(.caption)
                .frame(width: DownloadColumns.eta, alignment: .leading)

                // Actions
                ActionsCell(item: item)
                    .frame(width: DownloadColumns.actions, alignment: .trailing)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let hash = item.checksumSHA256, !hash.isEmpty {
                        HStack(spacing: 6) {
                            Text("SHA-256:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(hash)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(2)
                                .textSelection(.enabled)
                            Button {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(hash, forType: .string)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .help("Copy SHA-256")
                        }
                    } else if item.status == .completed {
                        Text("SHA-256: computing…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let segs = item.segments, !segs.isEmpty {
                        ChunkDetails(segments: segs)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isExpanded
            ? AnyView(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial))
            : AnyView(EmptyView())
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(isExpanded ? 0.18 : (isHovering ? 0.12 : 0)), lineWidth: (isExpanded || isHovering) ? 1 : 0)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { self.isHovering = hovering }
        }
        .onTapGesture { isExpanded.toggle() }
    }
}

private struct HistoryRow: View {
    let item: DownloadItem
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        HStack(spacing: 8) {
            // File info
            HStack(spacing: 8) {
                Image(nsImage: fileIcon(for: item))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .cornerRadius(4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.finalFileName ?? item.url.lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                    Text(item.url.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let hash = item.checksumSHA256, !hash.isEmpty {
                        HStack(spacing: 6) {
                            Text("SHA-256:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(hash)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(hash, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .help("Copy SHA-256")
                        }
                    } else if item.status == .completed {
                        Text("SHA-256: computing…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            // Size
                    Group {
                if let total = item.totalBytes, total > 0 {
                    Text(formatBytes(total))
                } else {
                    Text(formatBytes(item.receivedBytes))
                }
            }
            .font(.caption)
            .frame(width: DownloadColumns.size, alignment: .leading)

            // Status
            let (icon, color, text) = statusPresentation(for: item.status)
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .imageScale(.small)
                    .foregroundStyle(color)
                Text(text)
                    .font(.caption)
            }
            .frame(width: DownloadColumns.status, alignment: .leading)

            // Progress (final)
            Group {
                if let total = item.totalBytes, total > 0 {
                    Text(formatPercent(received: min(item.receivedBytes, total), total: total))
                } else {
                    Text("—")
                }
            }
            .font(.caption)
            .frame(width: DownloadColumns.progress, alignment: .leading)

            // Chunks (thumbnail)
            ChunkMiniBar(segments: item.segments ?? [])
                .frame(width: DownloadColumns.chunks, height: 12, alignment: .leading)

            // Speed (final=0)
            Text(item.status == .downloading ? formatSpeedCompact(item.speedBytesPerSec) : "0")
                .font(.caption)
                .frame(width: DownloadColumns.speed, alignment: .leading)

            // ETA (none in history)
            Text("—")
                .font(.caption)
                .frame(width: DownloadColumns.eta, alignment: .leading)

            HStack(spacing: 6) {
                if item.status == .completed {
                    Button { appModel.openDownloadedFile(item: item) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc")
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.white)
                            Text("Open")
                        }
                    }
                        .actionProminent(tint: .blue)
                    Button { appModel.revealDownloadedFile(item: item) } label: { Label("Reveal", systemImage: "folder") }
                        .actionBordered()
                } else if item.status == .deleted {
                    Button { appModel.restore(item: item) } label: { Label("Restore", systemImage: "arrow.uturn.left") }
                        .actionProminent(tint: .green)
                    Button(role: .destructive) { appModel.deletePermanently(item: item) } label: { Label("Delete Permanently", systemImage: "trash.slash") }
                        .actionBordered(tint: .red)
                } else {
                    Button(role: .destructive) { appModel.delete(item: item) } label: { Label("Delete", systemImage: "trash") }
                        .actionBordered(tint: .red)
                }
            }
            .controlSize(.small)
            .frame(width: DownloadColumns.actions, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
// MARK: - Helpers
private struct Hoverable<Content: View>: View {
    @State private var hovering = false
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        content()
            .scaleEffect(hovering ? 1.03 : 1)
            .shadow(color: .black.opacity(hovering ? 0.12 : 0), radius: 5, x: 0, y: 1)
            .animation(.easeInOut(duration: 0.12), value: hovering)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) { self.hovering = hovering }
            }
    }
}

// MARK: - Unified button styling with per-button hover
private struct HoverEffect: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.03 : 1)
            .shadow(color: .black.opacity(hovering ? 0.12 : 0), radius: 5, x: 0, y: 1)
            .animation(.easeInOut(duration: 0.12), value: hovering)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) { self.hovering = hovering }
            }
    }
}

private extension View {
    func actionProminent(tint: Color) -> some View {
        self
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .modifier(HoverEffect())
    }
    func actionBordered(tint: Color? = nil) -> some View {
        var view = AnyView(self.buttonStyle(.bordered).modifier(HoverEffect()))
        if let t = tint { view = AnyView(view.tint(t)) }
        return view
    }
}
private struct ChunkMiniBar: View {
    let segments: [Segment]

    private var totalLength: Double {
        guard !segments.isEmpty else { return 0 }
        return Double(segments.reduce(0) { $0 + ($1.rangeEnd - $1.rangeStart + 1) })
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(segments, id: \.index) { seg in
                    let len = Double(seg.rangeEnd - seg.rangeStart + 1)
                    let width = totalLength > 0 ? geo.size.width * (len / totalLength) : 0
                    ZStack(alignment: .leading) {
                        Rectangle().fill(background(seg))
                        Rectangle().fill(foreground(seg))
                            .frame(width: width * progress(seg))
                    }
                    .frame(width: max(1, width), height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .help("#\(seg.index) \(seg.state)")
                }
            }
        }
    }

    private func progress(_ s: Segment) -> CGFloat {
        let len = max(1, s.rangeEnd - s.rangeStart + 1)
        return CGFloat(Double(min(max(0, s.received), len)) / Double(len))
    }

    private func background(_ s: Segment) -> Color {
        switch s.state {
        case "done": return Color.green.opacity(0.25)
        case "downloading": return Color.blue.opacity(0.2)
        case "paused": return Color.yellow.opacity(0.2)
        case "failed": return Color.red.opacity(0.2)
        default: return Color.gray.opacity(0.15)
        }
    }

    private func foreground(_ s: Segment) -> Color {
        switch s.state {
        case "done": return .green
        case "downloading": return .blue
        case "paused": return .yellow
        case "failed": return .red
        default: return .gray
        }
    }
}

// Detailed chunk list for an item
private struct ChunkDetails: View {
    let segments: [Segment]

    private var grid: [GridItem] { [GridItem(.adaptive(minimum: 260), spacing: 8, alignment: .top)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Chunks (\(segments.count))", systemImage: "square.stack.3d.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            LazyVGrid(columns: grid, spacing: 8) {
                ForEach(segments.sorted(by: { $0.index < $1.index }), id: \.index) { seg in
                    SegmentCard(segment: seg)
                }
            }
        }
    }

    private struct SegmentCard: View {
        let segment: Segment
        private var totalLen: Int64 { max(1, segment.rangeEnd - segment.rangeStart + 1) }
        private var fraction: Double { min(1.0, Double(segment.received) / Double(totalLen)) }
        private var color: Color { ChunkDetails.colorFor(segment.state) }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("#\(segment.index)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.15)))
                        .foregroundStyle(color)
                    Spacer(minLength: 4)
                    StatusBadge(state: segment.state, color: color)
                }
                ProgressView(value: Double(segment.received), total: Double(totalLen))
                    .controlSize(.small)
                HStack {
                    Text("\(formatBytes(segment.received)) / \(formatBytes(totalLen))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.15)))
        }
    }

    private struct StatusBadge: View {
        let state: String
        let color: Color
        var body: some View {
            HStack(spacing: 4) {
                Image(systemName: icon(for: state))
                    .font(.caption2)
                Text(title(for: state))
                    .font(.caption2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
        }

        private func title(for state: String) -> String {
            switch state {
            case "done": return "Done"
            case "downloading": return "Active"
            case "paused": return "Paused"
            case "failed": return "Failed"
            default: return state.capitalized
            }
        }
        private func icon(for state: String) -> String {
            switch state {
            case "done": return "checkmark.circle.fill"
            case "downloading": return "arrow.down.circle.fill"
            case "paused": return "pause.circle.fill"
            case "failed": return "xmark.octagon.fill"
            default: return "circle"
            }
        }
    }

    private static func colorFor(_ state: String) -> Color {
        switch state {
        case "done": return .green
        case "downloading": return .blue
        case "paused": return .yellow
        case "failed": return .red
        default: return .secondary
        }
    }
}

private func formatSpeed(_ v: Double) -> String {
    guard v > 0 else { return "—" }
    let units = ["B/s", "KB/s", "MB/s", "GB/s"]
    var value = v
    var idx = 0
    while value > 1024 && idx < units.count - 1 {
        value /= 1024
        idx += 1
    }
    return String(format: "%.1f %@", value, units[idx])
}

private func formatSpeedCompact(_ v: Double) -> String {
    guard v > 0 else { return "—" }
    let units = ["B", "K", "M", "G"]
    var value = v
    var idx = 0
    while value > 1024 && idx < units.count - 1 {
        value /= 1024
        idx += 1
    }
    return String(format: "%.0f%@/s", value, units[idx])
}

private func formatETA(_ s: Double) -> String {
    let secs = Int(s.rounded())
    let h = secs / 3600
    let m = (secs % 3600) / 60
    let sec = secs % 60
    if h > 0 { return String(format: "%dh %dm %ds", h, m, sec) }
    if m > 0 { return String(format: "%dm %ds", m, sec) }
    return String(format: "%ds", sec)
}

private func formatETACompact(_ s: Double) -> String {
    let secs = Int(s.rounded())
    let h = secs / 3600
    let m = (secs % 3600) / 60
    let sec = secs % 60
    if h > 0 { return "\(h)h" }
    if m > 0 { return "\(m)m" }
    return "\(sec)s"
}

private func bytesPair(received: Int64, total: Int64) -> String {
    "\(formatBytes(received)) / \(formatBytes(total))"
}

private func bytesPairKB(received: Int64, total: Int64) -> String {
    "\(formatBytesKB(received)) / \(formatBytesKB(total))"
}

private func bytesPairMBMixed(received: Int64, total: Int64) -> String {
    "\(formatBytesMB3(received)) / \(formatBytesMB1(total))"
}

private func formatBytes(_ v: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(max(0, v))
    var idx = 0
    while value >= 1024.0 && idx < units.count - 1 {
        value /= 1024.0
        idx += 1
    }
    if idx == 0 { return String(format: "%.0f %@", value, units[idx]) }
    return String(format: "%.1f %@", value, units[idx])
}

// Force KB formatting for active downloads
private func formatBytesKB(_ v: Int64) -> String {
    let kb = Double(max(0, v)) / 1024.0
    if kb < 10 { return String(format: "%.2f KB", kb) }
    if kb < 100 { return String(format: "%.1f KB", kb) }
    return String(format: "%.0f KB", kb)
}

// Force MB with fixed 3 decimals for received (0.000 MB)
private func formatBytesMB3(_ v: Int64) -> String {
    let mb = Double(max(0, v)) / (1024.0 * 1024.0)
    return String(format: "%.3f MB", mb)
}

// Force MB with fixed 1 decimal for total file size (0.0 MB)
private func formatBytesMB1(_ v: Int64) -> String {
    let mb = Double(max(0, v)) / (1024.0 * 1024.0)
    return String(format: "%.1f MB", mb)
}

private func formatPercent(received: Int64, total: Int64) -> String {
    guard total > 0 else { return "—" }
    let clampedReceived = max(Int64(0), min(received, total))
    let percent = Int((Double(clampedReceived) / Double(total) * 100).rounded())
    return "\(percent)%"
}

private func statusPresentation(for status: DownloadStatus) -> (String, Color, String) {
    switch status {
    case .queued: return ("clock", .gray, "Queued")
    case .fetchingMetadata: return ("arrow.triangle.2.circlepath", .secondary, "Preparing")
    case .downloading: return ("arrow.down.circle.fill", .blue, "Downloading")
    case .paused: return ("pause.circle.fill", .yellow, "Paused")
        case .reconnecting: return ("wifi.exclamationmark", .orange, "Reconnecting")
    case .completed: return ("checkmark.circle.fill", .green, "Completed")
    case .failed: return ("xmark.octagon.fill", .red, "Failed")
    case .canceled: return ("stop.circle.fill", .gray, "Stopped")
    case .deleted: return ("trash", .gray, "Deleted")
    }
}

private func fileIcon(for item: DownloadItem) -> NSImage {
    let filename = item.finalFileName ?? item.url.lastPathComponent
    let ext = (filename as NSString).pathExtension.lowercased()
    if ext.isEmpty {
        return NSImage(named: NSImage.multipleDocumentsName) ?? NSImage(size: NSSize(width: 24, height: 24))
    }
    if let type = UTType(filenameExtension: ext) {
        return NSWorkspace.shared.icon(for: type)
    }
    return NSImage(named: NSImage.multipleDocumentsName) ?? NSImage(size: NSSize(width: 24, height: 24))
}

// File type sort key (normalized extension; empty types sort last)
private func typeKey(for item: DownloadItem) -> String {
    let filename = item.finalFileName ?? item.url.lastPathComponent
    let ext = (filename as NSString).pathExtension.lowercased()
    if ext.isEmpty { return "~zzz" } // push unknown types to end
    return ext
}

// Size value (prefer totalBytes, else receivedBytes)
private func sizeValue(for item: DownloadItem) -> Int64 {
    if let total = item.totalBytes, total > 0 { return total }
    return max(0, item.receivedBytes)
}

// Name ascending helper
private func nameAsc(_ a: DownloadItem, _ b: DownloadItem) -> Bool {
    let na = (a.finalFileName?.isEmpty == false ? a.finalFileName! : a.url.lastPathComponent)
    let nb = (b.finalFileName?.isEmpty == false ? b.finalFileName! : b.url.lastPathComponent)
    return na.localizedCaseInsensitiveCompare(nb) == .orderedAscending
}

private enum SortKey: String, CaseIterable, Hashable {
    case type, size, older, status, nameAZ, nameZA
    var title: String {
        switch self {
        case .type: return "Type"
        case .size: return "Size"
        case .older: return "Older"
        case .status: return "Status"
        case .nameAZ: return "A–Z"
        case .nameZA: return "Z–A"
        }
    }
}

// MARK: - Action Cell with hover support

private struct ActionsCell: View {
    let item: DownloadItem
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        HStack(spacing: 6) {
            if item.status == .downloading {
                Button { appModel.pause(item: item) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.fill")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.white)
                        Text("Pause")
                    }
                }
                    .help("Pause")
                    .actionProminent(tint: .orange)
                Button { appModel.cancel(item: item) } label: { Label("Cancel", systemImage: "xmark") }
                    .help("Cancel")
                    .actionBordered(tint: .red)
            } else if item.status == .paused || item.status == .failed || item.status == .queued || item.status == .reconnecting {
                Button { appModel.resume(item: item) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.white)
                        Text("Resume")
                    }
                }
                    .help("Resume")
                    .actionProminent(tint: .green)
                Button { appModel.cancel(item: item) } label: { Label("Cancel", systemImage: "xmark") }
                    .help("Cancel")
                    .actionBordered(tint: .red)
            } else if item.status == .canceled {
                HStack(spacing: 6) {
                    Button { appModel.resume(item: item) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.white)
                            Text("Resume")
                        }
                    }
                        .help("Resume")
                        .actionProminent(tint: .green)
                    Button(role: .destructive) { appModel.delete(item: item) } label: { Label("Delete", systemImage: "trash") }
                        .help("Delete")
                        .actionBordered(tint: .red)
                }
            } else if item.status == .completed {
                HStack(spacing: 6) {
                    Button { appModel.openDownloadedFile(item: item) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc")
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.white)
                            Text("Open")
                        }
                    }
                        .help("Open the downloaded file")
                        .actionProminent(tint: .blue)
                    Button { appModel.revealDownloadedFile(item: item) } label: { Label("Open File Location", systemImage: "folder") }
                        .help("Reveal the file in Finder")
                        .actionBordered()
                }
            }
        }
        .controlSize(.small)
    }
}



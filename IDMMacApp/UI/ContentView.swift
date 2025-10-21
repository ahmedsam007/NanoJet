import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DownloadEngine
import Foundation
import Combine

// MARK: - Notification View
struct NotificationView: View {
    let notification: AppNotification
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    
    var body: some View {
        notificationContent
            .scaleEffect(isVisible ? 1.0 : 0.9)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
            .onAppear {
                withAnimation {
                    isVisible = true
                }
            }
    }
    
    private var notificationContent: some View {
        HStack(spacing: 12) {
            notificationIcon
            notificationText
            Spacer()
            notificationActions
            dismissButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(notification.type.color.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    private var notificationIcon: some View {
        Image(systemName: notification.type.icon)
            .foregroundStyle(notification.type.color)
            .imageScale(.medium)
            .symbolRenderingMode(.hierarchical)
    }
    
    private var notificationText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(notification.title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
            
            if !notification.message.isEmpty {
                Text(notification.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    @ViewBuilder
    private var notificationActions: some View {
        if !notification.actions.isEmpty {
            HStack(spacing: 8) {
                ForEach(notification.actions) { action in
                    actionButton(for: action)
                }
            }
        }
    }
    
    @ViewBuilder
    private func actionButton(for action: NotificationAction) -> some View {
        let button = Button(action.title) {
            action.action()
            onDismiss()
        }
        .controlSize(.small)
        
        if action.style == .primary {
            button
                .buttonStyle(BorderedProminentButtonStyle())
                .if(action.style.tint != nil) { view in
                    view.tint(action.style.tint!)
                }
        } else {
            button
                .buttonStyle(BorderedButtonStyle())
                .if(action.style.tint != nil) { view in
                    view.tint(action.style.tint!)
                }
        }
    }
    
    private var dismissButton: some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Dismiss")
    }
}

// MARK: - Notification Container
struct NotificationContainer: View {
    @StateObject private var notificationManager = NotificationManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(notificationManager.notifications) { notification in
                NotificationView(notification: notification) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        notificationManager.dismiss(notification.id)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .frame(maxWidth: 400) // Limit width instead of taking full width
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: notificationManager.notifications.count)
    }
}

extension Notification.Name {
    static let showYouTubeSetup = Notification.Name("showYouTubeSetup")
}

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
    @State private var headerSort: (field: HeaderSortField, ascending: Bool)? = nil
    @State private var showChangeFolderDialog: Bool = false
    @State private var showYouTubeSetup: Bool = false
    @State private var showFeedbackSheet: Bool = false
    @State private var showAboutWindow: Bool = false
    @State private var feedbackText: String = ""
    @State private var feedbackSending: Bool = false
    @State private var feedbackError: String? = nil

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
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
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
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(minWidth: 260, idealWidth: 360, maxWidth: 520, alignment: .leading)
                    .layoutPriority(1)

                    if !selectedItemIds.isEmpty {
                        Label("\(selectedItemIds.count) selected", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

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
                    .menuStyle(DefaultMenuStyle())
                    .controlSize(.mini)
                    .fixedSize()
                    if historyFilter == .completed {
                        Button(role: .destructive) {
                            appModel.clearCompleted()
                        } label: {
                            Label("Clear Finished", systemImage: "trash")
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                Divider()

                let filteredItems = appModel.items.filter { historyFilter.includes($0.status) }
                let sortedItems: [DownloadItem] = {
                    if let hdr = headerSort {
                        return filteredItems.sorted { a, b in
                            switch hdr.field {
                            case .file:
                                let asc = nameAsc(a, b)
                                return hdr.ascending ? asc : !asc
                            case .date:
                                if a.createdAt == b.createdAt { return nameAsc(a, b) }
                                return hdr.ascending ? (a.createdAt < b.createdAt) : (a.createdAt > b.createdAt)
                            case .size:
                                let sa = sizeValue(for: a)
                                let sb = sizeValue(for: b)
                                if sa == sb { return nameAsc(a, b) }
                                return hdr.ascending ? (sa < sb) : (sa > sb)
                            case .status:
                                let ra = a.status.rawValue
                                let rb = b.status.rawValue
                                if ra == rb { return nameAsc(a, b) }
                                return hdr.ascending ? (ra < rb) : (ra > rb)
                            case .resumable:
                                let ra = a.supportsRanges ? 1 : 0
                                let rb = b.supportsRanges ? 1 : 0
                                if ra == rb { return nameAsc(a, b) }
                                return hdr.ascending ? (ra < rb) : (ra > rb)
                            case .progress:
                                let pa = progressValue(for: a)
                                let pb = progressValue(for: b)
                                if pa == pb { return nameAsc(a, b) }
                                return hdr.ascending ? (pa < pb) : (pa > pb)
                            case .chunks:
                                let ca = completedChunks(for: a)
                                let cb = completedChunks(for: b)
                                if ca == cb { return nameAsc(a, b) }
                                return hdr.ascending ? (ca < cb) : (ca > cb)
                            case .speed:
                                let sa = a.speedBytesPerSec
                                let sb = b.speedBytesPerSec
                                if sa == sb { return nameAsc(a, b) }
                                return hdr.ascending ? (sa < sb) : (sa > sb)
                            case .eta:
                                let ea = a.etaSeconds ?? Double.greatestFiniteMagnitude
                                let eb = b.etaSeconds ?? Double.greatestFiniteMagnitude
                                if ea == eb { return nameAsc(a, b) }
                                return hdr.ascending ? (ea < eb) : (ea > eb)
                            }
                        }
                    } else if historyFilter == .all {
                        // Default for "All" tab: newest first so recent items are visible at the top
                        return filteredItems.sorted { a, b in
                            if a.createdAt == b.createdAt { return nameAsc(a, b) }
                            return a.createdAt > b.createdAt
                        }
                    } else {
                        return filteredItems.sorted { a, b in
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
                    }
                }()
                // Horizontal scroll container keeps headers and rows moving together
                GeometryReader { geo in
                    let availableWidth = geo.size.width
                    let showChunks = availableWidth > 780
                    let showSpeedEta = availableWidth > 730
                    let showResumableDate = availableWidth > 680
                    let showSize = availableWidth > 600
                    VStack(alignment: .leading, spacing: 0) {
                        DownloadsHeaderRow(
                            allItemIds: sortedItems.map { $0.id },
                            selectedIds: $selectedItemIds,
                            currentSort: headerSort,
                            onHeaderTap: { field in toggleHeaderSort(field) },
                            showChunks: showChunks,
                            showSpeedEta: showSpeedEta,
                            showResumableDate: showResumableDate,
                            showSize: showSize
                        )
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                            .frame(maxHeight: .infinity, alignment: .center)
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
                                        ),
                                        currentFilter: historyFilter,
                                        showChunks: showChunks,
                                        showSpeedEta: showSpeedEta,
                                        showResumableDate: showResumableDate,
                                        showSize: showSize
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
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(0)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.blue)
                    }
                }
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    TextField("", text: $inputURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 360, idealWidth: 480, maxWidth: 560)
                        .overlay(
                            ZStack {
                                // Leading placeholder that stays visible when empty and does not overlap trailing icons
                                if inputURL.isEmpty {
                                    HStack {
                                        Text("Paste URL to download")
                                            .foregroundStyle(.secondary)
                                            .allowsHitTesting(false)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.leading, 8)
                                    .padding(.trailing, 150) // reserve space for trailing controls (clear + download)
                                }
                                // Trailing buttons inside the field: Clear and Download (with trendy blur mask behind)
                                HStack {
                                    Spacer()
                                    ZStack(alignment: .trailing) {
                                        let hasValidURL = AppViewModel.validDownloadURL(from: inputURL.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
                                        // Smooth, layered white shadow behind the Download button; only when actionable
                                        if hasValidURL {
                                            HStack(spacing: 0) {
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(Color.primary.opacity(0.01))
                                                    .frame(width: 130, height: 28)
                                                    .shadow(color: .white.opacity(0.95), radius: 14, x: 0, y: 0)
                                                    .shadow(color: .white.opacity(0.90), radius: 28, x: 0, y: 0)
                                                    .shadow(color: .white.opacity(0.90), radius: 56, x: 0, y: 0)
                                            }
                                            .padding(.trailing, 0)
                                            .shadow(color: .clear, radius: 0)
                                            .allowsHitTesting(false)
                                        }

                                        HStack(spacing: 8) {
                                            if !inputURL.isEmpty {
                                                Button(action: { inputURL = "" }) {
                                                    Image(systemName: "xmark")
                                                        .foregroundStyle(.primary)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 4)
                                                        .background(
                                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                                .fill(Color(NSColor.controlBackgroundColor))
                                                        )
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                                .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                                                        )
                                                        .shadow(color: Color.primary.opacity(0.09), radius: 3, x: 0, y: 1)
                                                }
                                                .buttonStyle(.borderless)
                                                .help("Clear")
                                            }
                                            Button(action: { submitURL() }) {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "arrow.down.circle")
                                                    Text("Download")
                                                }
                                                .foregroundStyle(hasValidURL ? .white : Color.primary.opacity(0.8))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .fill(hasValidURL ? Color.blue : Color.gray.opacity(0.35))
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .stroke((hasValidURL ? Color.blue.opacity(0.95) : Color.gray.opacity(0.3)), lineWidth: 1)
                                                )
                                                .shadow(color: hasValidURL ? .black.opacity(0.15) : .black.opacity(0.05), radius: 6, x: 0, y: 2)
                                            }
                                            .buttonStyle(.borderless)
                                            .disabled(!hasValidURL)
                                            .help(hasValidURL ? "Download" : "Paste a valid URL to enable")
                                        }
                                        .font(.caption)
                                        .padding(.trailing, 8)
                                    }
                                }
                            }
                        )
                        .onSubmit { submitURL() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle(isOn: $appModel.shutdownWhenDone) {
                        Label("Shut down when done", systemImage: "power")
                    }
                    .help("Automatically shut down the Mac after all downloads finish")
                    Divider()
                    Button {
                        openWindow(id: "scheduler")
                    } label: {
                        Label("Schedule Downloads", systemImage: "calendar")
                    }
                    Divider()
                    Button {
                        showChangeFolderDialog = true
                    } label: {
                        Label("Change Download Folder…", systemImage: "folder")
                    }
                    Divider()
                    Button {
                        appModel.requestAutomationPermission()
                    } label: {
                        Label("Allow Automation…", systemImage: "bolt.badge.a")
                    }
                    .help("Prompt macOS to grant Automation access to System Events")
                    Button {
                        appModel.openAutomationPrivacyPane()
                    } label: {
                        Label("Open Automation Privacy…", systemImage: "lock")
                    }
                    Divider()
                    Button {
                        UpdaterManager.shared.checkForUpdates()
                    } label: {
                        Label("Check for Updates…", systemImage: "arrow.down.circle")
                    }
                    Button {
                        showFeedbackSheet = true
                    } label: {
                        Label("Send Feedback", systemImage: "envelope")
                    }
                    Button(action: {
                        if let url = URL(string: "https://paypal.me/slmofti/5") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Label("Support Development", systemImage: "heart.fill")
                    }
                    Divider()
                    Button {
                        showAboutWindow = true
                    } label: {
                        Label("About IDMMac", systemImage: "info.circle")
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(DefaultMenuStyle())
                .controlSize(.small)
            }
        }
        .sheet(isPresented: $showChangeFolderDialog) {
            ChangeDownloadFolderDialog(isPresented: $showChangeFolderDialog)
        }
        .sheet(isPresented: $showYouTubeSetup) {
            YouTubeSetupView()
        }
        .sheet(isPresented: $showAboutWindow) {
            AboutView()
        }
        .sheet(isPresented: $showFeedbackSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Send Feedback to Developer")
                    .font(.title3.bold())
                Text("Describe your problem, feature request or feedback below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextEditor(text: $feedbackText)
                    .frame(minHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                if let err = feedbackError {
                    Text(err)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                HStack {
                    Spacer()
                    Button("Send") {
                        feedbackSending = true
                        feedbackError = nil
                        let body = feedbackText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "mailto:info@ahmedsam.com?subject=Feedback%20from%20IDMMac&body=\(body)") {
                            NSWorkspace.shared.open(url)
                            showFeedbackSheet = false
                            feedbackText = ""
                        } else {
                            feedbackError = "Could not open email client. Please send feedback manually to info@ahmedsam.com."
                        }
                        feedbackSending = false
                    }.disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || feedbackSending)
                    Button("Cancel") {
                        showFeedbackSheet = false
                        feedbackText = ""
                    }
                }
            }
            .padding(24)
            .frame(minWidth: 400, idealWidth: 440, maxWidth: 520)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showYouTubeSetup)) { _ in
            showYouTubeSetup = true
        }
        .onAppear {
            // Prefill from clipboard on first appearance if empty and clipboard has a valid URL
            let pb = NSPasteboard.general
            if inputURL.isEmpty, let str = pb.string(forType: .string), let url = AppViewModel.validDownloadURL(from: str) {
                inputURL = url.absoluteString
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Auto-fill when returning to the app, without auto-starting a download
            let pb = NSPasteboard.general
            if inputURL.isEmpty, let str = pb.string(forType: .string), let url = AppViewModel.validDownloadURL(from: str) {
                inputURL = url.absoluteString
            }
        }
        .overlay(alignment: .topTrailing) {
            NotificationContainer()
                .padding(.top, 8)
                .padding(.trailing, 16)
        }
    }
}

// MARK: - Log Viewer Window
struct LogViewer: View {
    let item: DownloadItem
    @State private var text: String = "Loading…"
    @State private var timer: Timer?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.finalFileName ?? item.url.lastPathComponent)
                    .font(.headline)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 4)
            SelectableTextView(text: text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(12)
        .frame(minWidth: 640, minHeight: 420)
        .onAppear { reload(); startAutoRefresh() }
        .onDisappear { timer?.invalidate(); timer = nil }
    }
    private func reload() {
        let url = DownloadLogger.logFileURL(for: item.id)
        if let str = try? String(contentsOf: url) {
            text = str
        } else {
            text = "Log is empty."
        }
    }
    private func startAutoRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in reload() }
        RunLoop.main.add(timer!, forMode: .common)
    }
}

// MARK: - URL Submission helper
private extension ContentView {
    func submitURL() {
        let trimmed = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = AppViewModel.validDownloadURL(from: trimmed) else { return }
        let isDuplicateActive = appModel.items.contains { $0.url == url && [.queued, .fetchingMetadata, .downloading, .reconnecting].contains($0.status) }
        
        if isDuplicateActive {
            let continueAction = NotificationAction(
                title: "Continue Anyway",
                style: .primary
            ) {
                self.appModel.enqueue(urlString: url.absoluteString, allowDuplicate: true) { _, _ in
                    self.inputURL = ""
                }
            }
            
            NotificationManager.shared.showWarning(
                title: "Duplicate Download",
                message: "This link is already queued or downloading.",
                actions: [continueAction]
            )
        } else {
            appModel.enqueue(urlString: url.absoluteString) { success, errorMsg in
                if !success, let errorMsg = errorMsg {
                    // Determine notification type and actions based on error message
                    if errorMsg.lowercased().contains("yt-dlp not found") {
                        let installAction = NotificationAction(
                            title: "Install yt-dlp",
                            style: .primary
                        ) {
                            NotificationCenter.default.post(name: .showYouTubeSetup, object: nil)
                        }
                        
                        NotificationManager.shared.showError(
                            title: "YouTube Download Error",
                            message: errorMsg,
                            actions: [installAction]
                        )
                    } else if errorMsg.lowercased().contains("cookies") || errorMsg.lowercased().contains("sign in") || errorMsg.lowercased().contains("age") || errorMsg.lowercased().contains("consent") {
                        let guideAction = NotificationAction(
                            title: "Learn How",
                            style: .primary
                        ) {
                            if let url = URL(string: "https://github.com/yt-dlp/yt-dlp#readme") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        
                        NotificationManager.shared.showWarning(
                            title: "YouTube Download Issue",
                            message: errorMsg,
                            actions: [guideAction]
                        )
                    } else {
                        NotificationManager.shared.showError(
                            title: "Download Error",
                            message: errorMsg
                        )
                    }
                } else {
                    inputURL = ""
                }
            }
        }
    }
}

// MARK: - Folder selection helper
private extension ContentView {
    // kept for potential reuse
    func selectDefaultDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                UserDefaults.standard.set(url.path, forKey: "downloadDirectoryPath")
                if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(bookmark, forKey: "downloadDirectoryBookmark")
                }
            }
        }
    }
}

// MARK: - Sorting helpers
private extension ContentView {
    func toggleHeaderSort(_ field: HeaderSortField) {
        if let current = headerSort {
            if current.field == field {
                if current.ascending {
                    headerSort = (field, false)
                } else {
                    headerSort = nil // third tap resets to default
                }
            } else {
                headerSort = (field, true)
            }
        } else {
            headerSort = (field, true)
        }
    }

    func progressValue(for item: DownloadItem) -> Double {
        guard let total = item.totalBytes, total > 0 else { return 0 }
        let received = max(Int64(0), min(item.receivedBytes, total))
        return Double(received) / Double(total)
    }

    func completedChunks(for item: DownloadItem) -> Int {
        guard let segs = item.segments, !segs.isEmpty else { return 0 }
        return segs.reduce(0) { acc, s in
            let need = s.rangeEnd - s.rangeStart + 1
            return acc + ((s.received >= need) ? 1 : 0)
        }
    }
}

// MARK: - Glass styling
private struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }
}


private extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
    
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
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
                                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                        )
                        .frame(width: 46, height: 24)
                        .shadow(color: configuration.isOn ? Color.green.opacity(0.25) : .clear, radius: 8, x: 0, y: 2)
                    Circle()
                        .fill(Color(NSColor.controlBackgroundColor))
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
                    .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
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
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Change Download Folder Dialog
private struct ChangeDownloadFolderDialog: View {
    @Binding var isPresented: Bool
    @State private var selectedPath: String = UserDefaults.standard.string(forKey: "downloadDirectoryPath") ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                Text("Change Download Folder")
                    .font(.title3.weight(.semibold))
            }
            Text("Choose where new downloads will be saved by default. You can change this anytime.")
                .foregroundStyle(.secondary)
                .font(.callout)

            HStack(spacing: 8) {
                Text(selectedPath.isEmpty ? "Currently: Downloads (default)" : selectedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button {
                    openPanel()
                } label: {
                    Label("Browse…", systemImage: "ellipsis.rectangle")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button("Use Default") {
                    selectedPath = ""
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.bordered)
                Button {
                    applySelection()
                    isPresented = false
                } label: {
                    Label("Use This Folder", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 520)
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                selectedPath = url.path
                if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(bookmark, forKey: "downloadDirectoryBookmark_temp")
                }
            }
        }
    }

    private func applySelection() {
        if selectedPath.isEmpty {
            UserDefaults.standard.removeObject(forKey: "downloadDirectoryPath")
            UserDefaults.standard.removeObject(forKey: "downloadDirectoryBookmark")
            UserDefaults.standard.removeObject(forKey: "downloadDirectoryBookmark_temp")
            return
        }
        UserDefaults.standard.set(selectedPath, forKey: "downloadDirectoryPath")
        if let temp = UserDefaults.standard.data(forKey: "downloadDirectoryBookmark_temp") {
            UserDefaults.standard.set(temp, forKey: "downloadDirectoryBookmark")
            UserDefaults.standard.removeObject(forKey: "downloadDirectoryBookmark_temp")
        }
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
    static let date: CGFloat = 170
    static let status: CGFloat = 120
    static let resumable: CGFloat = 85
    static let progress: CGFloat = 120
    static let chunks: CGFloat = 160
    static let speed: CGFloat = 55
    static let eta: CGFloat = 45
    static let actions: CGFloat = 180
}

private enum HeaderSortField: Hashable {
    case file
    case date
    case size
    case status
    case resumable
    case progress
    case chunks
    case speed
    case eta
}

// Header text insets so titles align with the start of the primary text (not icons) in rows
private struct ColumnInsets {
    static let fileTextLeading: CGFloat = 40 // chevron + spacing + file icon + spacing
    static let statusTextLeading: CGFloat = 10 // status icon + spacing (nudged left for alignment)
}

// Table layout metrics for horizontal scrolling
private struct TableLayout {
    static let checkboxWidth: CGFloat = 18
    static let hSpacing: CGFloat = 8
    static let fileMinWidth: CGFloat = 220
    static var totalMinWidth: CGFloat {
        checkboxWidth + hSpacing +
        fileMinWidth + hSpacing +
        DownloadColumns.date + hSpacing +
        DownloadColumns.size + hSpacing +
        DownloadColumns.status + hSpacing +
        DownloadColumns.resumable + hSpacing +
        DownloadColumns.progress + hSpacing +
        DownloadColumns.chunks + hSpacing +
        DownloadColumns.speed + hSpacing +
        DownloadColumns.eta + hSpacing +
        DownloadColumns.actions
    }
}

private struct DownloadsHeaderRow: View {
    let allItemIds: [UUID]
    @Binding var selectedIds: Set<UUID>
    let currentSort: (field: HeaderSortField, ascending: Bool)?
    let onHeaderTap: (HeaderSortField) -> Void
    var showChunks: Bool = true
    var showSpeedEta: Bool = true
    var showResumableDate: Bool = true
    var showSize: Bool = true
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
            HStack(spacing: 0) {
                Spacer().frame(width: ColumnInsets.fileTextLeading)
                headerLabel(title: "File", field: .file)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
            if showResumableDate {
                headerLabel(title: "Added", field: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, -8)
                    .frame(width: DownloadColumns.date, alignment: .leading)
            }
            if showSize {
                headerLabel(title: "Size", field: .size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, -8)
                    .frame(width: DownloadColumns.size, alignment: .leading)
            }
            // Status is always visible
            HStack(spacing: 0) {
                Spacer().frame(width: ColumnInsets.statusTextLeading)
                headerLabel(title: "Status", field: .status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, -8)
            }
            .frame(width: DownloadColumns.status, alignment: .leading)
            if showResumableDate {
                headerLabel(title: "Resumable", field: .resumable)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, -8)
                    .frame(width: DownloadColumns.resumable, alignment: .leading)
            }
            // Progress is always visible
            headerLabel(title: "Progress", field: .progress)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, -8)
                .frame(width: DownloadColumns.progress, alignment: .leading)
            if showChunks {
                headerLabel(title: "Chunks", field: .chunks)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, -8)
                    .frame(width: DownloadColumns.chunks, alignment: .leading)
            }
            if showSpeedEta {
                headerLabel(title: "Speed", field: .speed)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, -8)
                    .frame(width: DownloadColumns.speed, alignment: .leading)
                headerLabel(title: "ETA", field: .eta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, -8)
                    .frame(width: DownloadColumns.eta, alignment: .leading)
            }
            // Actions should only show at widest sizes (showChunks is a proxy for wide size)
            if showChunks {
                Text("Actions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, -8)
                    .frame(width: DownloadColumns.actions, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func headerLabel(title: String, field: HeaderSortField) -> some View {
        let isActive = currentSort?.field == field
        let ascending = currentSort?.ascending ?? true
        let chevron = ascending ? "chevron.up" : "chevron.down"
        HStack(spacing: 4) {
            Text(title)
            if isActive {
                Image(systemName: chevron)
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onHeaderTap(field) }
    }
}

private struct DownloadRow: View {
    let item: DownloadItem
    @Binding var isSelected: Bool
    @Binding var isExpanded: Bool
    let currentFilter: HistoryFilter
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var isHovering: Bool = false
    var showChunks: Bool = true
    var showSpeedEta: Bool = true
    var showResumableDate: Bool = true
    var showSize: Bool = true

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
                if showResumableDate {
                    Text(formatDateTimeShort(item.createdAt))
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .frame(width: DownloadColumns.date, alignment: .leading)
                }
                if showSize {
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
                }
                // Status (always visible)
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
                if showResumableDate {
                    Text(item.supportsRanges ? "Yes" : "No")
                        .font(.caption)
                        .foregroundStyle(item.supportsRanges ? .green : .secondary)
                        .frame(width: DownloadColumns.resumable, alignment: .leading)
                }
                // Progress (always visible)
                Group {
                    if item.status == .completed {
                        HStack(spacing: 6) {
                            Text("100%")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 16, height: 16)
                        }
                    } else if (item.status == .downloading || item.status == .paused), let total = item.totalBytes, total > 0 {
                        HStack(spacing: 6) {
                            Text(formatPercent(received: min(item.receivedBytes, total), total: total))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                            ProgressView(value: Double(item.receivedBytes), total: Double(total))
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                                .frame(width: 16, height: 16)
                        }
                    } else if (item.status == .downloading || item.status == .paused) {
                        HStack(spacing: 6) {
                            // Reserve space so the circle is aligned even when percentage is unknown
                            Text("100%")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.clear)
                                .frame(width: 40, alignment: .trailing)
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                                .frame(width: 16, height: 16)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Text("—")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 16, height: 16)
                        }
                    }
                }
                .frame(width: DownloadColumns.progress, alignment: .leading)
                if showChunks {
                    ChunkMiniBar(segments: item.segments ?? [])
                        .frame(width: DownloadColumns.chunks, height: 12, alignment: .leading)
                }
                if showSpeedEta {
                    Text(formatSpeedCompact(item.speedBytesPerSec))
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: DownloadColumns.speed, alignment: .leading)
                    Group {
                        if let eta = item.etaSeconds, eta > 0 { Text(formatETACompact(eta)) } else { Text("—") }
                    }
                    .font(.caption)
                    .frame(width: DownloadColumns.eta, alignment: .leading)
                }
                if showChunks {
                    ActionsCell(item: item, currentFilter: currentFilter)
                        .frame(width: DownloadColumns.actions, alignment: .trailing)
                }
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Link:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(item.url.absoluteString)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Button {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(item.url.absoluteString, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Copy download link")
                    }
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
                    HStack(spacing: 8) {
                        Button {
                            openWindow(id: "log-viewer", value: item.id)
                        } label: {
                            Label("Open Log", systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Open detailed log in a separate window")
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
            ? AnyView(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(NSColor.controlBackgroundColor)))
            : AnyView(EmptyView())
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(isExpanded ? 0.18 : (isHovering ? 0.12 : 0)), lineWidth: (isExpanded || isHovering) ? 1 : 0)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contextMenu {
            switch item.status {
            case .downloading:
                Button {
                    appModel.pause(item: item)
                } label: { Label("Pause", systemImage: "pause.fill") }
                Button {
                    appModel.cancel(item: item)
                } label: { Label("Cancel", systemImage: "xmark") }
            case .fetchingMetadata:
                Button {
                    appModel.cancel(item: item)
                } label: { Label("Cancel", systemImage: "xmark") }
            case .paused, .queued, .reconnecting:
                Button {
                    appModel.resume(item: item)
                } label: { Label("Resume", systemImage: "play.fill") }
                Button {
                    appModel.cancel(item: item)
                } label: { Label("Cancel", systemImage: "xmark") }
            case .failed:
                Button {
                    appModel.resume(item: item)
                } label: { Label("Resume", systemImage: "play.fill") }
                Button {
                    appModel.cancel(item: item)
                } label: { Label("Cancel", systemImage: "xmark") }
                Divider()
                Button {
                    appModel.retryDownload(item: item)
                } label: { Label("Re-Download File", systemImage: "arrow.clockwise") }
            case .canceled:
                Button(role: .destructive) {
                    appModel.delete(item: item)
                } label: { Label("Delete", systemImage: "trash") }
            case .completed:
                Button {
                    appModel.openDownloadedFile(item: item)
                } label: { Label("Open", systemImage: "doc") }
                Button {
                    appModel.revealDownloadedFile(item: item)
                } label: { Label("Open Location", systemImage: "folder") }
                Divider()
                Button {
                    appModel.retryDownload(item: item)
                } label: { Label("Re-Download File", systemImage: "arrow.clockwise") }
            case .deleted:
                if currentFilter == .deleted {
                    Button(role: .destructive) {
                        appModel.deletePermanently(item: item)
                    } label: { Label("Delete Permanently", systemImage: "trash.slash") }
                } else {
                    Button {
                        appModel.restore(item: item)
                    } label: { Label("Restore", systemImage: "arrow.uturn.left") }
                    Button(role: .destructive) {
                        appModel.deletePermanently(item: item)
                    } label: { Label("Delete Permanently", systemImage: "trash.slash") }
                }
            }
            // Schedule for unfinished or queued items
            if [.queued, .fetchingMetadata, .downloading, .paused, .reconnecting, .failed].contains(item.status) {
                Divider()
                Button {
                    openWindow(id: "scheduler")
                } label: { Label("Schedule", systemImage: "calendar") }
            }
        }
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
            // Date/time
            Text(formatDateTimeShort(item.createdAt))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: DownloadColumns.date, alignment: .leading)

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
                if item.status == .completed {
                    Text("100%")
                } else if let total = item.totalBytes, total > 0 {
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

private func formatDateTimeShort(_ d: Date) -> String {
    let df = DateFormatter()
    df.dateStyle = .short
    df.timeStyle = .short
    return df.string(from: d)
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
    let currentFilter: HistoryFilter
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        HStack(spacing: 6) {
            if item.status == .downloading {
                Button { appModel.pause(item: item) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.fill")
                        Text("Pause")
                    }
                }
                .help("Pause")
                .actionProminent(tint: .orange)
                Button { appModel.cancel(item: item) } label: { Label("Cancel", systemImage: "xmark") }
                .help("Cancel")
                .actionBordered(tint: .red)
            } else if item.status == .fetchingMetadata {
                Button { appModel.cancel(item: item) } label: { Label("Cancel", systemImage: "xmark") }
                .help("Cancel")
                .actionBordered(tint: .red)
            } else if item.status == .paused || item.status == .queued || item.status == .reconnecting {
                Button { appModel.resume(item: item) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Resume")
                    }
                }
                .help("Resume")
                .actionProminent(tint: .green)
                Button { appModel.cancel(item: item) } label: { Label("Cancel", systemImage: "xmark") }
                .help("Cancel")
                .actionBordered(tint: .red)
            } else if item.status == .failed {
                Button { appModel.resume(item: item) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Resume")
                    }
                }
                .help("Resume the failed download")
                .actionProminent(tint: .green)
                Button { appModel.retryDownload(item: item) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Re-Download")
                    }
                }
                .help("Start fresh download from beginning")
                .actionBordered(tint: .blue)
            } else if item.status == .canceled {
                Button(role: .destructive) { appModel.delete(item: item) } label: { Label("Delete", systemImage: "trash") }
                .help("Delete")
                .actionBordered(tint: .red)
            } else if item.status == .completed {
                HStack(spacing: 6) {
                    Button { appModel.openDownloadedFile(item: item) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc")
                            Text("Open")
                        }
                    }
                    .help("Open the downloaded file")
                    .actionProminent(tint: .blue)
                    Button { appModel.revealDownloadedFile(item: item) } label: { Label("Open Location", systemImage: "folder") }
                    .help("Reveal the file in Finder")
                    .actionBordered()
                }
            } else if item.status == .deleted {
                if currentFilter == .deleted {
                    Button(role: .destructive) { appModel.deletePermanently(item: item) } label: { Label("Delete Permanently", systemImage: "trash.slash") }
                    .actionBordered(tint: .red)
                } else {
                    Button { appModel.restore(item: item) } label: { Label("Restore", systemImage: "arrow.uturn.left") }
                    .actionProminent(tint: .green)
                    Button(role: .destructive) { appModel.deletePermanently(item: item) } label: { Label("Delete Permanently", systemImage: "trash.slash") }
                    .actionBordered(tint: .red)
                }
            }
        }
        .controlSize(.small)
    }
}

private struct SelectableTextView: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        if let container = textView.textContainer {
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            container.widthTracksTextView = true
        }
        textView.string = text
        let scroll = NSScrollView()
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor.textBackgroundColor
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.documentView = textView
        return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let tv = nsView.documentView as? NSTextView {
            if tv.string != text {
                tv.string = text
            }
        }
    }
}



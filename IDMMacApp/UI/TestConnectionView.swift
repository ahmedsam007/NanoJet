import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TestConnectionView: View {
    let testURL: URL
    @EnvironmentObject private var appModel: AppViewModel
    @State private var running = false
    @State private var report: TestReport?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.title2).bold()
                Spacer()
                // Online/Offline status indicator
                Label(appModel.connectionStatus == .online ? "Online" : (appModel.connectionStatus == .offline ? "Offline" : "Checking…"),
                      systemImage: appModel.connectionStatus == .online ? "checkmark.seal.fill" : (appModel.connectionStatus == .offline ? "xmark.seal.fill" : "clock"))
                    .foregroundStyle(appModel.connectionStatus == .online ? .green : (appModel.connectionStatus == .offline ? .red : .secondary))
                    .font(.subheadline)
            }

            TextField("URL to test", text: .constant(testURL.absoluteString))
                .textFieldStyle(.roundedBorder)
                .disabled(true)

            if running {
                ProgressView("Running diagnostics…")
                    .progressViewStyle(.linear)
            }

            if let r = report {
                SummaryPills(report: r, online: appModel.connectionStatus == .online)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionView(title: "Network Path", systemImage: "point.3.connected.trianglepath.dotted", lines: {
                            let interfaces = r.path.interfaces.joined(separator: ", ")
                            let expensive = r.path.isExpensive ? "Yes" : "No"
                            let constrained = r.path.isConstrained ? "Yes" : "No"
                            let ipv4 = r.path.supportsIPv4 ? "Yes" : "No"
                            let ipv6 = r.path.supportsIPv6 ? "Yes" : "No"
                            return [
                                "Status: \(r.path.status)",
                                "Interfaces: \(interfaces)",
                                "Expensive: \(expensive), Constrained: \(constrained)",
                                "IPv4: \(ipv4), IPv6: \(ipv6)"
                            ]
                        }())
                        SectionView(title: "Protocol", systemImage: "globe", lines: {
                            let http = r.protocolInfo.httpProtocol ?? "-"
                            let tls = r.protocolInfo.tlsVersion ?? "-"
                            let cipher = r.protocolInfo.tlsCipher ?? "-"
                            return [
                                "HTTP: \(http)",
                                "TLS: \(tls)",
                                "Cipher: \(cipher)",
                                "Reused Conn: \(yesNo(r.protocolInfo.connectionReused))",
                                "Proxy Used: \(yesNo(r.protocolInfo.usedProxy))"
                            ]
                        }())
                        SectionView(title: "Timings", systemImage: "clock", lines: [
                            "DNS: \(ms(r.timings.dnsMs))",
                            "Connect: \(ms(r.timings.connectMs))",
                            "TLS: \(ms(r.timings.tlsMs))",
                            "TTFB: \(ms(r.timings.ttfbMs))"
                        ])
                        SectionView(title: "Server", systemImage: "server.rack", lines: {
                            let acceptRanges = yesNo(r.server.acceptRanges)
                            let contentLength = r.server.contentLength.map { "\($0) bytes" } ?? "-"
                            let etag = r.server.etag ?? "-"
                            let lastMod = r.server.lastModified ?? "-"
                            let encoding = r.server.contentEncoding ?? "-"
                            let redirects = r.server.redirects.isEmpty ? "-" : r.server.redirects.joined(separator: " -> ")
                            return [
                                "Accept-Ranges: \(acceptRanges)",
                                "Content-Length: \(contentLength)",
                                "ETag: \(etag)",
                                "Last-Modified: \(lastMod)",
                                "Encoding: \(encoding)",
                                "Redirects: \(redirects)"
                            ]
                        }())
                        SectionView(title: "Performance (sample)", systemImage: "speedometer", lines: [
                            "Bytes: \(r.performance.sampledBytes)",
                            String(format: "Duration: %.2fs", r.performance.durationSec),
                            String(format: "Average: %.2f Mbit/s", r.performance.averageMbps)
                        ])
                        SectionView(title: "System", systemImage: "internaldrive", lines: [
                            String(format: "Disk free: %.2f GB", r.system.diskFreeGB ?? .nan),
                            String(format: "Write test: %.2f MB/s", r.system.writeTestMBps ?? .nan)
                        ])
                        SectionView(title: "Proxy", systemImage: "arrow.triangle.2.circlepath", lines: {
                            let active = r.proxy.systemProxyActive ? "Yes" : "No"
                            let pac = r.proxy.pacUrl ?? "-"
                            return [
                                "System Proxy Active: \(active)",
                                "PAC: \(pac)"
                            ]
                        }())
                        SectionView(title: "Security", systemImage: "lock.shield", lines: [
                            r.security.certExpiresInDays.map { "Cert expires in: \($0) days" } ?? "Cert expiry: -"
                        ])
                        SectionView(title: "Resume Support", systemImage: "arrow.triangle.2.circlepath", lines: [
                            r.resumeSupported ? "Likely supported ✅" : "Unknown/No ❔"
                        ])
                    }
                    .padding(.vertical, 8)
                }

                // Copy/Save actions moved to bottom bar
            }

            if let e = errorText {
                Text("Error: \(e)").foregroundColor(.red)
            }

            HStack(spacing: 8) {
                Button("Copy JSON") {
                    if let r = report { copyJSON(r) }
                }
                .disabled(report == nil)

                Button("Save Report…") {
                    if let r = report { saveJSON(r) }
                }
                .disabled(report == nil)

                Spacer()

                Button(running ? "Cancel" : "Run Test") {
                    if running { return }
                    runTest()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(running)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 520)
    }

    private func runTest() {
        running = true
        errorText = nil
        report = nil
        Task {
            do {
                let tester = ConnectionTester()
                let r = try await tester.run(for: testURL)
                await MainActor.run {
                    self.report = r
                    self.running = false
                }
            } catch {
                await MainActor.run {
                    self.errorText = error.localizedDescription
                    self.running = false
                }
            }
        }
    }

    private func copyJSON(_ r: TestReport) {
        do {
            let data = try JSONEncoder.pretty().encode(r)
            let str = String(data: data, encoding: .utf8) ?? "{}"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(str, forType: .string)
        } catch {
            self.errorText = "Copy failed: \(error.localizedDescription)"
        }
    }

    private func saveJSON(_ r: TestReport) {
        do {
            let data = try JSONEncoder.pretty().encode(r)
            let panel = NSSavePanel()
            if #available(macOS 12.0, *) {
                panel.allowedContentTypes = [UTType.json]
            } else {
                panel.allowedFileTypes = ["json"]
            }
            panel.nameFieldStringValue = "ConnectionReport.json"
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
            }
        } catch {
            self.errorText = "Save failed: \(error.localizedDescription)"
        }
    }

    private func ms(_ v: Double?) -> String { v.map { String(format: "%.0f ms", $0) } ?? "-" }
    private func yesNo(_ v: Bool?) -> String { v == true ? "Yes" : (v == false ? "No" : "-") }
}

private struct SummaryPills: View {
    let report: TestReport
    var online: Bool = false
    var body: some View {
        HStack {
            pill(icon: online ? "checkmark.seal.fill" : "xmark.seal.fill",
                 title: "Reachability",
                 value: online ? "ONLINE" : "OFFLINE",
                 color: online ? .green : .red)
            pill(icon: "globe", title: "Protocol", value: report.protocolInfo.httpProtocol ?? "-", color: .blue)
            pill(icon: "lock.shield", title: "TLS", value: report.protocolInfo.tlsVersion ?? "-", color: .teal)
            pill(icon: "speedometer", title: "Speed", value: String(format: "%.1f Mbit/s", report.performance.averageMbps), color: .purple)
            pill(icon: "arrow.triangle.2.circlepath", title: "Resume", value: report.resumeSupported ? "Yes" : "No", color: report.resumeSupported ? .green : .gray)
        }
    }
    func pill(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).bold()
            Text(value)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.15))
        .cornerRadius(8)
    }
}

private struct SectionView: View {
    let title: String
    var systemImage: String? = nil
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).foregroundStyle(.secondary) }
                Text(title).font(.headline)
            }
            ForEach(lines, id: \.self) { Text($0).font(.callout).foregroundColor(.secondary) }
            Divider().padding(.top, 6)
        }
    }
}

private extension JSONEncoder {
    static func pretty() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }
}



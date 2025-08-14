import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ConnectionDiagnosticsView: View {
    let report: TestReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                Text("Connection Diagnostics").font(.title2).bold()
                Text(report.url.absoluteString).font(.caption).foregroundStyle(.secondary)

                // One-glance summary pills
                summaryPills

                // Drill-down sections
                section(label: Label("Network Path", systemImage: "point.3.connected.trianglepath.dotted")) {
                    LabeledContent("Status") { Text(report.path.status) }
                    LabeledContent("Interfaces") { Text(report.path.interfaces.joined(separator: ", ")) }
                    LabeledContent("Cost/Constraints") {
                        Text("Expensive: \(yn(report.path.isExpensive))  Constrained: \(yn(report.path.isConstrained))")
                    }
                    LabeledContent("IP Versions") {
                        Text("IPv4: \(yn(report.path.supportsIPv4))  IPv6: \(yn(report.path.supportsIPv6))")
                    }
                }

                section(label: Label("Protocol", systemImage: "globe")) {
                    LabeledContent("HTTP") { Text(report.protocolInfo.httpProtocol ?? "-") }
                    LabeledContent("TLS") { Text(report.protocolInfo.tlsVersion ?? "-") }
                    LabeledContent("Cipher") { Text(report.protocolInfo.tlsCipher ?? "-") }
                    LabeledContent("Reused/Proxy") {
                        Text("Reused: \(yn(report.protocolInfo.connectionReused))  Proxy: \(yn(report.protocolInfo.usedProxy))")
                    }
                }

                section(label: Label("Server", systemImage: "server.rack")) {
                    LabeledContent("Accept-Ranges") { Text(yn(report.server.acceptRanges)) }
                    LabeledContent("Content-Length") { Text(report.server.contentLength.map(String.init) ?? "-") }
                    LabeledContent("ETag") { Text(report.server.etag ?? "-") }
                    LabeledContent("Last-Modified") { Text(report.server.lastModified ?? "-") }
                    LabeledContent("Encoding") { Text(report.server.contentEncoding ?? "-") }
                    if !report.server.redirects.isEmpty {
                        LabeledContent("Redirects") { Text(report.server.redirects.joined(separator: " → ")) }
                    }
                }

                // Timings
                section(label: Label("Timings", systemImage: "clock")) {
                    LabeledContent("DNS (ms)") { Text(fmt(report.timings.dnsMs)) }
                    LabeledContent("Connect (ms)") { Text(fmt(report.timings.connectMs)) }
                    LabeledContent("TLS (ms)") { Text(fmt(report.timings.tlsMs)) }
                    LabeledContent("TTFB (ms)") { Text(fmt(report.timings.ttfbMs)) }
                }

                section(label: Label("Performance", systemImage: "speedometer")) {
                    LabeledContent("Sampled") {
                        Text("\(report.performance.sampledBytes) bytes in \(String(format: "%.2fs", report.performance.durationSec))")
                    }
                    LabeledContent("Throughput") { Text(formatMBps(report.performance.averageMbps / 8.0)) }
                }

                section(label: Label("System", systemImage: "internaldrive")) {
                    LabeledContent("Disk Free") { Text(report.system.diskFreeGB.map { String(format: "%.1f GB", $0) } ?? "-") }
                    LabeledContent("Disk Write") { Text(report.system.writeTestMBps.map { String(format: "%.1f MB/s", $0) } ?? "-") }
                }

                section(label: Label("Security", systemImage: "lock.shield")) {
                    LabeledContent("Certificate") { Text("Expires in: \(report.security.certExpiresInDays.map(String.init) ?? "?") days") }
                }

                section(label: Label("Proxies", systemImage: "arrow.triangle.2.circlepath")) {
                    LabeledContent("Active") { Text(report.proxy.systemProxyActive ? "Yes" : "No") }
                    LabeledContent("PAC URL") { Text(report.proxy.pacUrl ?? "-") }
                }

                // Resume Support
                section(label: Label("Resume Support", systemImage: "arrow.triangle.2.circlepath")) {
                    LabeledContent("Supported") { Text(report.resumeSupported ? "Yes" : "No") }
                }

                // Actions
                HStack(spacing: 12) {
                    Button { copyJSON(report) } label: { Label("Copy Report", systemImage: "doc.on.doc") }
                    Button { saveText(report) } label: { Label("Save as .txt", systemImage: "square.and.arrow.down") }
                }
                .padding(.top, 8)
            }
            .padding(16)
        }
        .frame(minWidth: 680, minHeight: 560)
    }

    // MARK: - Summary
    private var summaryPills: some View {
        let reachable = report.path.status == "satisfied"
        let http = report.protocolInfo.httpProtocol ?? "?"
        let tls = report.protocolInfo.tlsVersion ?? "?"
        let iface = primaryInterface(report.path.interfaces)
        let ttfb = fmt(report.timings.ttfbMs)
        let mbps = formatMBps(report.performance.averageMbps / 8.0)
        let resume = report.resumeSupported
        return HStack(spacing: 10) {
            pill(icon: reachable ? "checkmark.seal.fill" : "xmark.seal.fill", color: reachable ? .green : .red, title: "Reachable", value: reachable ? "ONLINE" : "OFFLINE")
            pill(icon: "globe", color: .blue, title: "HTTP/TLS", value: "\(http)/\(tls)")
            pill(icon: "wifi", color: .teal, title: "Link", value: iface)
            pill(icon: "clock", color: .indigo, title: "TTFB", value: "\(ttfb) ms")
            pill(icon: "speedometer", color: .purple, title: "Speed", value: mbps)
            pill(icon: "arrow.triangle.2.circlepath", color: resume ? .green : .gray, title: "Resume", value: resume ? "Yes" : "No")
        }
    }

    private func pill(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).bold()
            Text(value)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Helpers
    private func section<Content: View>(label: Label<Text, Image>, @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) { content() }
                .padding(.top, 6)
        } label: {
            label.font(.headline)
        }
    }

    private func fmt(_ v: Double?) -> String { v.map { String(format: "%.0f", $0) } ?? "—" }
    private func yn(_ v: Bool) -> String { v ? "Yes" : "No" }
    private func yn(_ v: Bool?) -> String { v == true ? "Yes" : (v == false ? "No" : "-") }
    private func formatMBps(_ mbPerSec: Double) -> String { String(format: "%.1f MB/s", max(0, mbPerSec)) }
    private func primaryInterface(_ interfaces: [String]) -> String {
        if interfaces.contains("wifi") { return "Wi‑Fi" }
        if interfaces.contains("wired") { return "Wired" }
        return interfaces.first?.capitalized ?? "—"
    }

    private func copyJSON(_ r: TestReport) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(r), let str = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(str, forType: .string)
        }
    }

    private func saveText(_ r: TestReport) {
        let text = generateTextReport(r)
        let panel = NSSavePanel()
        if #available(macOS 12.0, *) { panel.allowedContentTypes = [.plainText] }
        panel.nameFieldStringValue = "ConnectionReport.txt"
        if panel.runModal() == .OK, let url = panel.url { try? text.data(using: .utf8)?.write(to: url) }
    }

    private func generateTextReport(_ r: TestReport) -> String {
        var lines: [String] = []
        lines.append("URL: \(r.url.absoluteString)")
        lines.append("Time: \(ISO8601DateFormatter().string(from: r.timestamp))")
        lines.append("")
        lines.append("Reachable: \(r.path.status)")
        lines.append("Protocol: \(r.protocolInfo.httpProtocol ?? "-") / \(r.protocolInfo.tlsVersion ?? "-")")
        lines.append("Interface: \(primaryInterface(r.path.interfaces))")
        lines.append("TTFB: \(fmt(r.timings.ttfbMs)) ms")
        lines.append("Speed: \(formatMBps(r.performance.averageMbps / 8.0))")
        lines.append("Resume: \(r.resumeSupported ? "Yes" : "No")")
        lines.append("")
        lines.append("-- Server --")
        lines.append("Accept-Ranges: \(String(describing: r.server.acceptRanges))")
        lines.append("Content-Length: \(String(describing: r.server.contentLength))")
        lines.append("ETag: \(r.server.etag ?? "-")")
        lines.append("Last-Modified: \(r.server.lastModified ?? "-")")
        lines.append("Encoding: \(r.server.contentEncoding ?? "-")")
        if !r.server.redirects.isEmpty { lines.append("Redirects: \(r.server.redirects.joined(separator: " -> "))") }
        return lines.joined(separator: "\n")
    }
}



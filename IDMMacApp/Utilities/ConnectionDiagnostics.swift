import Foundation
import Network
import Security

// MARK: - Data Models

public struct TestReport: Codable {
    public var timestamp: Date = Date()
    public var url: URL

    public var path: PathInfo
    public var timings: Timings
    public var protocolInfo: ProtocolInfo
    public var server: ServerInfo
    public var performance: Performance
    public var system: SystemInfo
    public var proxy: ProxyInfo
    public var security: SecurityInfo

    public var resumeSupported: Bool
    public var notes: String?
}

public struct PathInfo: Codable {
    public var status: String            // satisfied / unsatisfied / requiresConnection
    public var interfaces: [String]      // wifi, wired, loopback, other
    public var isExpensive: Bool
    public var isConstrained: Bool
    public var supportsIPv4: Bool
    public var supportsIPv6: Bool
}

public struct Timings: Codable {
    public var dnsMs: Double?
    public var connectMs: Double?
    public var tlsMs: Double?
    public var ttfbMs: Double?
}

public struct ProtocolInfo: Codable {
    public var httpProtocol: String?     // "h2", "http/1.1", "h3"
    public var tlsVersion: String?
    public var tlsCipher: String?
    public var connectionReused: Bool?
    public var usedProxy: Bool?
}

public struct ServerInfo: Codable {
    public var acceptRanges: Bool?
    public var contentLength: Int64?
    public var etag: String?
    public var lastModified: String?
    public var contentEncoding: String?
    public var redirects: [String] = []
    public var rawHeaders: [String: String] = [:]
}

public struct Performance: Codable {
    public var sampledBytes: Int64
    public var durationSec: Double
    public var averageMbps: Double
}

public struct SystemInfo: Codable {
    public var diskFreeGB: Double?
    public var writeTestMBps: Double?
}

public struct ProxyInfo: Codable {
    public var systemProxyActive: Bool
    public var pacUrl: String?
}

public struct SecurityInfo: Codable {
    public var certExpiresInDays: Int?
    public var ocspStapled: Bool?    // not populated in this starter; left for future
}

// MARK: - ConnectionTester

public final class ConnectionTester: NSObject {
    // Per-run storage
    private var lastMetrics: URLSessionTaskMetrics?
    private var capturedRedirects: [String] = []
    private var leafCertNotAfter: Date?

    public override init() { super.init() }

    /// Run the diagnostics for a given URL. This performs:
    /// - NWPath snapshot
    /// - HEAD (or tiny Range GET) to read server capabilities/headers
    /// - Small Range download to collect URLSessionTaskMetrics (DNS/connect/TLS/TTFB) and measure throughput
    /// - Disk free space + quick write test in Downloads directory
    public func run(for url: URL, sampleBytes: Int = 5_000_000) async throws -> TestReport {
        // 1) Network path snapshot
        let pathInfo = await snapshotPath()

        // 2) Probe server via HEAD (fallback to Range GET)
        let probe = try await headOrProbe(url: url)

        // 3) Measure a small download (Range 0..N-1)
        let perf = try await sampleDownload(url: url, bytesToFetch: sampleBytes)

        // 4) Build timings & protocol from collected metrics
        let timings = timingsFromMetrics(lastMetrics)
        let proto = protocolFromMetrics(lastMetrics)

        // 5) System info (disk + write test)
        let system = try systemInfo()

        // 6) Proxy system settings (coarse)
        let proxy = systemProxyInfo(metrics: lastMetrics)

        // 7) Security info (certificate expiry from auth challenge if available)
        let security = securityInfo()

        // Assemble report
        let report = TestReport(
            url: url,
            path: pathInfo,
            timings: timings,
            protocolInfo: proto,
            server: probe,
            performance: perf,
            system: system,
            proxy: proxy,
            security: security,
            resumeSupported: (probe.acceptRanges ?? false) || perf.sampledBytes > 0
        )
        return report
    }

    // MARK: Path (NWPathMonitor)

    private func snapshotPath(timeout: TimeInterval = 3.0) async -> PathInfo {
        await withCheckedContinuation { cont in
            let monitor = NWPathMonitor()
            let q = DispatchQueue(label: "PathMonitor")
            let gate = OneTimeGate()
            monitor.pathUpdateHandler = { path in
                gate.run {
                    monitor.cancel()
                    cont.resume(returning: PathInfo(from: path))
                }
            }
            monitor.start(queue: q)
            q.asyncAfter(deadline: .now() + timeout) {
                gate.run {
                    monitor.cancel()
                    cont.resume(returning: PathInfo(status: "unknown",
                                                   interfaces: [],
                                                   isExpensive: false,
                                                   isConstrained: false,
                                                   supportsIPv4: false,
                                                   supportsIPv6: false))
                }
            }
        }
    }

    // MARK: HEAD / Probe

    private func headOrProbe(url: URL) async throws -> ServerInfo {
        // Try HEAD first
        var headReq = URLRequest(url: url)
        headReq.httpMethod = "HEAD"
        headReq.timeoutInterval = 15

        do {
            let (_, resp) = try await ephemeralSession().data(for: headReq)
            if let http = resp as? HTTPURLResponse {
                return parseServerInfo(from: http, acceptRangesOverride: nil)
            }
        } catch {
            // fall through to Range probe
        }

        // Fallback: Range GET bytes=0-0
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        req.timeoutInterval = 20

        let delegate = MetricsDelegate(owner: self)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let (_, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse {
            let accept = http.statusCode == 206 // partial content implies range support
            return parseServerInfo(from: http, acceptRangesOverride: accept)
        }
        return ServerInfo(acceptRanges: nil, contentLength: nil, etag: nil, lastModified: nil, contentEncoding: nil, redirects: capturedRedirects, rawHeaders: [:])
    }

    private func parseServerInfo(from http: HTTPURLResponse, acceptRangesOverride: Bool?) -> ServerInfo {
        var headers: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            headers["\(k)"] = "\(v)"
        }
        let cl = headers["Content-Length"].flatMap { Int64($0) }
        let acceptRanges = acceptRangesOverride ?? (headers["Accept-Ranges"]?.lowercased().contains("bytes") == true)
        return ServerInfo(
            acceptRanges: acceptRanges,
            contentLength: cl,
            etag: headers["ETag"],
            lastModified: headers["Last-Modified"],
            contentEncoding: headers["Content-Encoding"],
            redirects: capturedRedirects,
            rawHeaders: headers
        )
    }

    // MARK: Small download for metrics + throughput

    private func sampleDownload(url: URL, bytesToFetch: Int) async throws -> Performance {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("bytes=0-\(bytesToFetch - 1)", forHTTPHeaderField: "Range")

        let delegate = MetricsDelegate(owner: self)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

        let start = Date()
        let (data, _) = try await session.data(for: req)
        let duration = Date().timeIntervalSince(start)
        let bytes = Int64(data.count)
        let mbps = duration > 0 ? (Double(bytes) * 8.0 / duration) / 1_000_000.0 : 0 // bits/sec → Mbit/s

        return Performance(sampledBytes: bytes, durationSec: duration, averageMbps: mbps)
    }

    // MARK: System info (disk + write test)

    private func systemInfo() throws -> SystemInfo {
        // Destination: user's Downloads folder
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        var diskFree: Double?
        if let values = try? downloads.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let cap = values.volumeAvailableCapacityForImportantUsage {
            diskFree = Double(cap) / 1_000_000_000.0
        }

        // Quick write test ~16MB
        let tmpURL = downloads.appendingPathComponent(".idmmac_write_test.tmp")
        let size = 16 * 1_024 * 1_024
        let buf = Data(repeating: 0, count: size)
        let t0 = Date()
        try? buf.write(to: tmpURL, options: .atomic)
        let elapsed = Date().timeIntervalSince(t0)
        if FileManager.default.fileExists(atPath: tmpURL.path) {
            try? FileManager.default.removeItem(at: tmpURL)
        }
        let mbps = elapsed > 0 ? (Double(size) / 1_000_000.0) / elapsed : nil

        return SystemInfo(diskFreeGB: diskFree, writeTestMBps: mbps)
    }

    // MARK: Proxy info

    private func systemProxyInfo(metrics: URLSessionTaskMetrics?) -> ProxyInfo {
        var active = metrics?.transactionMetrics.first?.isProxyConnection ?? false
        var pac: String?

        if let dict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] {
            if let httpOn = dict[kCFNetworkProxiesHTTPEnable as String] as? NSNumber, httpOn.boolValue { active = true }
            if let httpsOn = dict[kCFNetworkProxiesHTTPSEnable as String] as? NSNumber, httpsOn.boolValue { active = true }
            if let socksOn = dict[kCFNetworkProxiesSOCKSEnable as String] as? NSNumber, socksOn.boolValue { active = true }
            pac = dict[kCFNetworkProxiesProxyAutoConfigURLString as String] as? String
        }
        return ProxyInfo(systemProxyActive: active, pacUrl: pac)
    }

    // MARK: Security info (certificate expiry if we saw a challenge)

    private func securityInfo() -> SecurityInfo {
        guard let notAfter = leafCertNotAfter else {
            return SecurityInfo(certExpiresInDays: nil, ocspStapled: nil)
        }
        let days = Int(ceil(notAfter.timeIntervalSince(Date()) / 86400.0))
        return SecurityInfo(certExpiresInDays: days, ocspStapled: nil)
    }

    // MARK: Helpers

    private func timingsFromMetrics(_ metrics: URLSessionTaskMetrics?) -> Timings {
        guard let t = metrics?.transactionMetrics.last else { return Timings(dnsMs: nil, connectMs: nil, tlsMs: nil, ttfbMs: nil) }
        func ms(_ a: Date?, _ b: Date?) -> Double? {
            guard let a, let b else { return nil }
            return b.timeIntervalSince(a) * 1000.0
        }
        let dns = ms(t.domainLookupStartDate, t.domainLookupEndDate)
        let connect = ms(t.connectStartDate, t.connectEndDate)
        let tls = ms(t.secureConnectionStartDate, t.secureConnectionEndDate)
        let ttfb = ms(t.requestStartDate, t.responseStartDate)
        return Timings(dnsMs: dns, connectMs: connect, tlsMs: tls, ttfbMs: ttfb)
    }

    private func protocolFromMetrics(_ metrics: URLSessionTaskMetrics?) -> ProtocolInfo {
        guard let t = metrics?.transactionMetrics.last else {
            return ProtocolInfo(httpProtocol: nil, tlsVersion: nil, tlsCipher: nil, connectionReused: nil, usedProxy: nil)
        }
        return ProtocolInfo(
            httpProtocol: t.networkProtocolName,
            tlsVersion: tlsVersionString(from: t.negotiatedTLSProtocolVersion),
            tlsCipher: tlsCipherString(from: t.negotiatedTLSCipherSuite),
            connectionReused: t.isReusedConnection,
            usedProxy: t.isProxyConnection
        )
    }

    private func tlsVersionString(from version: tls_protocol_version_t?) -> String? {
        guard let v = version else { return nil }
        switch v {
        case .TLSv10: return "TLS1.0"
        case .TLSv11: return "TLS1.1"
        case .TLSv12: return "TLS1.2"
        case .TLSv13: return "TLS1.3"
        default: return "TLS(?)"
        }
    }

    private func tlsCipherString(from suite: tls_ciphersuite_t?) -> String? {
        guard let s = suite else { return nil }
        return String(describing: s) // human-readable mapping can be added later
    }

    private func ephemeralSession() -> URLSession {
        URLSession(configuration: .ephemeral, delegate: MetricsDelegate(owner: self), delegateQueue: nil)
    }

    // Internal: called by delegate
    fileprivate func capture(metrics: URLSessionTaskMetrics) { self.lastMetrics = metrics }
    fileprivate func captureRedirect(from: URL?, to: URL?) {
        if let to { self.capturedRedirects.append(to.absoluteString) }
    }
    fileprivate func captureLeafExpiry(_ date: Date?) { self.leafCertNotAfter = date }
}

// MARK: - NWPath → PathInfo

private extension PathInfo {
    init(from path: NWPath) {
        func ifaceName(_ type: NWInterface.InterfaceType) -> String {
            switch type {
            case .wifi: return "wifi"
            case .wiredEthernet: return "wired"
            case .cellular: return "cellular"
            case .loopback: return "loopback"
            case .other: return "other"
            @unknown default: return "unknown"
            }
        }
        self.status = {
            switch path.status {
            case .satisfied: return "satisfied"
            case .unsatisfied: return "unsatisfied"
            case .requiresConnection: return "requiresConnection"
            @unknown default: return "unknown"
            }
        }()
        self.interfaces = path.availableInterfaces.map { ifaceName($0.type) }
        self.isExpensive = path.isExpensive
        self.isConstrained = path.isConstrained
        self.supportsIPv4 = path.supportsIPv4
        self.supportsIPv6 = path.supportsIPv6
    }
}

// MARK: - URLSession Delegates (metrics, redirects, TLS)

private final class MetricsDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    private weak var owner: ConnectionTester?

    init(owner: ConnectionTester) { self.owner = owner }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        owner?.captureRedirect(from: task.originalRequest?.url, to: request.url)
        return request
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        owner?.capture(metrics: metrics)
    }

    // Capture TLS trust to compute cert expiry
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if let trust = challenge.protectionSpace.serverTrust {
            // Extract notAfter from leaf certificate
            if let notAfter = leafNotAfterDate(from: trust) {
                owner?.captureLeafExpiry(notAfter)
            }
        }
        return (.performDefaultHandling, nil)
    }

    // Extract the "Not After" date from the leaf certificate
    private func leafNotAfterDate(from trust: SecTrust) -> Date? {
        // Use modern API to get certificate chain (macOS 12+)
        guard let certs = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = certs.first else { return nil }
        let keys: [CFString] = [kSecOIDX509V1ValidityNotAfter]
        guard let values = SecCertificateCopyValues(leaf, keys as CFArray, nil) as? [CFString: Any],
              let notAfterDict = values[kSecOIDX509V1ValidityNotAfter] as? [CFString: Any] else { return nil }
        if let date = notAfterDict[kSecPropertyKeyValue] as? Date {
            return date
        }
        if let ts = notAfterDict[kSecPropertyKeyValue] as? TimeInterval {
            // Fallback for legacy value type
            return Date(timeIntervalSinceReferenceDate: ts)
        }
        return nil
    }
}

// MARK: - Utilities

// NSLock is thread-safe but not formally Sendable. We only share this gate across a closure
// used by NWPathMonitor callbacks on a DispatchQueue. Mark as @unchecked Sendable to silence
// the capture warning while keeping behavior safe.
private final class OneTimeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasRun = false

    func run(_ block: () -> Void) {
        lock.lock()
        let shouldRun = !hasRun
        hasRun = true
        lock.unlock()
        if shouldRun { block() }
    }
}



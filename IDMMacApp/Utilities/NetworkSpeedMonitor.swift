import Foundation
import SystemConfiguration

/// Monitors network traffic and calculates real-time upload/download speeds
@MainActor
final class NetworkSpeedMonitor: ObservableObject {
    @Published var downloadSpeed: Double = 0.0  // bytes per second
    @Published var uploadSpeed: Double = 0.0    // bytes per second
    @Published var isMonitoring: Bool = false
    
    private var timer: Timer?
    private var previousDownloadBytes: UInt64 = 0
    private var previousUploadBytes: UInt64 = 0
    private var previousTimestamp: Date = Date()
    
    // Singleton for app-wide access
    static let shared = NetworkSpeedMonitor()
    
    private init() {}
    
    /// Start monitoring network speed
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // Get initial values
        let (down, up) = getCurrentNetworkBytes()
        previousDownloadBytes = down
        previousUploadBytes = up
        previousTimestamp = Date()
        
        // Update every second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateSpeeds()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    /// Stop monitoring network speed
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
        downloadSpeed = 0.0
        uploadSpeed = 0.0
    }
    
    private func updateSpeeds() {
        let currentTimestamp = Date()
        let timeInterval = currentTimestamp.timeIntervalSince(previousTimestamp)
        
        guard timeInterval > 0 else { return }
        
        let (currentDownload, currentUpload) = getCurrentNetworkBytes()
        
        print("NetworkSpeedMonitor: Current bytes - download: \(currentDownload), upload: \(currentUpload)")
        print("NetworkSpeedMonitor: Previous bytes - download: \(previousDownloadBytes), upload: \(previousUploadBytes)")
        
        // Calculate speed (bytes per second)
        let downloadDelta = currentDownload > previousDownloadBytes 
            ? Double(currentDownload - previousDownloadBytes) 
            : 0.0
        let uploadDelta = currentUpload > previousUploadBytes 
            ? Double(currentUpload - previousUploadBytes) 
            : 0.0
        
        downloadSpeed = downloadDelta / timeInterval
        uploadSpeed = uploadDelta / timeInterval
        
        print("NetworkSpeedMonitor: Speed - download: \(downloadSpeed) B/s, upload: \(uploadSpeed) B/s")
        
        // Update previous values
        previousDownloadBytes = currentDownload
        previousUploadBytes = currentUpload
        previousTimestamp = currentTimestamp
    }
    
    /// Get current network bytes transferred (download, upload)
    private func getCurrentNetworkBytes() -> (download: UInt64, upload: UInt64) {
        var download: UInt64 = 0
        var upload: UInt64 = 0
        var processedInterfaces: Set<String> = []
        
        // Get network interface statistics
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else {
            print("NetworkSpeedMonitor: Failed to get ifaddrs")
            return (0, 0)
        }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            
            // Only count active network interfaces (exclude loopback and bridge interfaces)
            guard !name.hasPrefix("lo"),
                  !name.hasPrefix("bridge"),
                  !name.hasPrefix("awdl"),
                  !name.hasPrefix("utun"),
                  !name.hasPrefix("llw") else { continue }
            
            // Only process each interface once (getifaddrs returns multiple entries per interface)
            guard !processedInterfaces.contains(name) else { continue }
            processedInterfaces.insert(name)
            
            // Check if this entry has link-level data (AF_LINK)
            guard interface.ifa_addr.pointee.sa_family == AF_LINK else { continue }
            
            // Extract if_data from the sockaddr
            if let data = interface.ifa_data {
                let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                let ibytes = UInt64(ifData.ifi_ibytes)
                let obytes = UInt64(ifData.ifi_obytes)
                
                print("NetworkSpeedMonitor: \(name) - download: \(ibytes), upload: \(obytes)")
                
                download += ibytes
                upload += obytes
            }
        }
        
        print("NetworkSpeedMonitor: Processed interfaces: \(processedInterfaces.joined(separator: ", "))")
        print("NetworkSpeedMonitor: Total - download: \(download), upload: \(upload)")
        
        return (download, upload)
    }
    
    // MARK: - Legacy method (not used, kept for reference)
    /// Get bytes transferred for a specific interface using route table
    private func getInterfaceBytesViaIOKit_OLD(name: String) -> (download: UInt64, upload: UInt64)? {
        // Use sysctl with route table to get interface statistics
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST, 0]
        var len: size_t = 0
        
        // Get required buffer size
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0 else {
            print("NetworkSpeedMonitor: Failed to get buffer size")
            return nil
        }
        
        // Allocate buffer
        var buffer = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buffer, &len, nil, 0) == 0 else {
            print("NetworkSpeedMonitor: Failed to get interface list")
            return nil
        }
        
        print("NetworkSpeedMonitor: Looking for interface '\(name)', buffer size: \(len)")
        
        // Parse buffer safely
        var offset = 0
        var foundInterfaces: [String] = []
        var msgCount = 0
        var ifinfo2Count = 0
        
        while offset + 16 < len {
            // Read message length and type
            let msgLen = Int(buffer.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
            })
            
            guard msgLen >= 16, offset + msgLen <= len else { break }
            
            let msgVersion = buffer[offset + 1]
            let msgType = buffer[offset + 2]
            
            msgCount += 1
            
            print("NetworkSpeedMonitor: Message \(msgCount): type=\(msgType), version=\(msgVersion), length=\(msgLen)")
            
            // RTM_IFINFO = 14 (0xe), RTM_IFINFO2 = 18 (0x12)
            if msgType == RTM_IFINFO || msgType == RTM_IFINFO2 {
                ifinfo2Count += 1
                
                // The sockaddr_dl comes right after if_msghdr2
                // if_msghdr2 size is variable but typically starts at a fixed offset
                // Let's scan for the sockaddr_dl by looking for AF_LINK (18)
                var sdlOffset = offset + 144  // Try typical offset first
                
                // Search for sockaddr_dl (family = AF_LINK = 18)
                var found = false
                for searchOffset in stride(from: offset + 100, to: min(offset + 250, buffer.count - 20), by: 4) {
                    if searchOffset + 1 < buffer.count && buffer[searchOffset + 1] == 18 {
                        sdlOffset = searchOffset
                        found = true
                        break
                    }
                }
                
                guard found, sdlOffset + 12 < buffer.count else {
                    print("NetworkSpeedMonitor: Could not find sockaddr_dl for message \(ifinfo2Count)")
                    offset += msgLen
                    continue
                }
                
                // Read interface name from sockaddr_dl
                let sdlNlen = Int(buffer[sdlOffset + 5])
                guard sdlNlen > 0, sdlNlen <= 16 else {
                    print("NetworkSpeedMonitor: Invalid name length: \(sdlNlen)")
                    offset += msgLen
                    continue
                }
                
                let nameStart = sdlOffset + 8
                guard nameStart + sdlNlen <= buffer.count else {
                    offset += msgLen
                    continue
                }
                
                let nameBytes = Array(buffer[nameStart..<(nameStart + sdlNlen)])
                if let ifName = String(bytes: nameBytes, encoding: .utf8) {
                    foundInterfaces.append(ifName)
                    print("NetworkSpeedMonitor: Found interface name: \(ifName)")
                    
                    if ifName == name {
                        // The if_data64 is embedded in if_msghdr2
                        // Starts after: msglen(2) + version(1) + type(1) + addrs(4) + flags(4) + index(2) + 
                        //               snd_len(4) + snd_maxlen(4) + snd_drops(4) + timer(4) = 30 bytes
                        // Then aligned to 8 bytes = 32 bytes
                        let dataOffset = offset + 32
                        
                        // In if_data64, after 64 bytes we find ifi_ibytes
                        let ibyteOffset = dataOffset + 64
                        let obyteOffset = dataOffset + 72
                        
                        guard obyteOffset + 8 <= buffer.count else {
                            offset += msgLen
                            continue
                        }
                        
                        let ibytes = buffer.withUnsafeBytes { ptr in
                            ptr.loadUnaligned(fromByteOffset: ibyteOffset, as: UInt64.self)
                        }
                        
                        let obytes = buffer.withUnsafeBytes { ptr in
                            ptr.loadUnaligned(fromByteOffset: obyteOffset, as: UInt64.self)
                        }
                        
                        print("NetworkSpeedMonitor: Found \(ifName) - download: \(ibytes), upload: \(obytes)")
                        return (download: ibytes, upload: obytes)
                    }
                }
            }
            
            offset += msgLen
        }
        
        print("NetworkSpeedMonitor: Processed \(msgCount) messages, \(ifinfo2Count) IFINFO2 messages")
        print("NetworkSpeedMonitor: Interface '\(name)' not found. Available interfaces: \(foundInterfaces.joined(separator: ", "))")
        return nil
    }
    
    /// Format speed for display (e.g., "1.5 MB/s")
    static func formatSpeed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec > 0 else { return "0 B/s" }
        
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = bytesPerSec
        var index = 0
        
        while value >= 1024.0 && index < units.count - 1 {
            value /= 1024.0
            index += 1
        }
        
        if index == 0 {
            return String(format: "%.0f %@", value, units[index])
        } else if value >= 100 {
            return String(format: "%.0f %@", value, units[index])
        } else if value >= 10 {
            return String(format: "%.1f %@", value, units[index])
        } else {
            return String(format: "%.2f %@", value, units[index])
        }
    }
    
    /// Format speed in compact form (e.g., "1.5M/s")
    static func formatSpeedCompact(_ bytesPerSec: Double) -> String {
        guard bytesPerSec > 0 else { return "0" }
        
        let units = ["B", "K", "M", "G"]
        var value = bytesPerSec
        var index = 0
        
        while value >= 1024.0 && index < units.count - 1 {
            value /= 1024.0
            index += 1
        }
        
        if index == 0 {
            return String(format: "%.0f%@", value, units[index])
        } else if value >= 100 {
            return String(format: "%.0f%@/s", value, units[index])
        } else if value >= 10 {
            return String(format: "%.1f%@/s", value, units[index])
        } else {
            return String(format: "%.2f%@/s", value, units[index])
        }
    }
}

// System constant
private let AF_LINK: UInt8 = 18

// C structs for network interface statistics
private struct if_data {
    var ifi_type: UInt8 = 0
    var ifi_typelen: UInt8 = 0
    var ifi_physical: UInt8 = 0
    var ifi_addrlen: UInt8 = 0
    var ifi_hdrlen: UInt8 = 0
    var ifi_recvquota: UInt8 = 0
    var ifi_xmitquota: UInt8 = 0
    var ifi_unused1: UInt8 = 0
    var ifi_mtu: UInt32 = 0
    var ifi_metric: UInt32 = 0
    var ifi_baudrate: UInt32 = 0
    var ifi_ipackets: UInt32 = 0
    var ifi_ierrors: UInt32 = 0
    var ifi_opackets: UInt32 = 0
    var ifi_oerrors: UInt32 = 0
    var ifi_collisions: UInt32 = 0
    var ifi_ibytes: UInt32 = 0
    var ifi_obytes: UInt32 = 0
    var ifi_imcasts: UInt32 = 0
    var ifi_omcasts: UInt32 = 0
    var ifi_iqdrops: UInt32 = 0
    var ifi_noproto: UInt32 = 0
    var ifi_recvtiming: UInt32 = 0
    var ifi_xmittiming: UInt32 = 0
    var ifi_lastchange: timeval = timeval()
    var ifi_unused2: UInt32 = 0
    var ifi_hwassist: UInt32 = 0
    var ifi_reserved1: UInt32 = 0
    var ifi_reserved2: UInt32 = 0
}

private struct if_data64 {
    var ifi_type: UInt8 = 0
    var ifi_typelen: UInt8 = 0
    var ifi_physical: UInt8 = 0
    var ifi_addrlen: UInt8 = 0
    var ifi_hdrlen: UInt8 = 0
    var ifi_recvquota: UInt8 = 0
    var ifi_xmitquota: UInt8 = 0
    var ifi_unused1: UInt8 = 0
    var ifi_mtu: UInt32 = 0
    var ifi_metric: UInt32 = 0
    var ifi_baudrate: UInt64 = 0
    var ifi_ipackets: UInt64 = 0
    var ifi_ierrors: UInt64 = 0
    var ifi_opackets: UInt64 = 0
    var ifi_oerrors: UInt64 = 0
    var ifi_collisions: UInt64 = 0
    var ifi_ibytes: UInt64 = 0
    var ifi_obytes: UInt64 = 0
    var ifi_imcasts: UInt64 = 0
    var ifi_omcasts: UInt64 = 0
    var ifi_iqdrops: UInt64 = 0
    var ifi_noproto: UInt64 = 0
    var ifi_recvtiming: UInt32 = 0
    var ifi_xmittiming: UInt32 = 0
    var ifi_lastchange: timeval = timeval()
}

private struct if_msghdr {
    var ifm_msglen: UInt16 = 0
    var ifm_version: UInt8 = 0
    var ifm_type: UInt8 = 0
    var ifm_addrs: Int32 = 0
    var ifm_flags: Int32 = 0
    var ifm_index: UInt16 = 0
    var ifm_data: if_data64 = if_data64()
}

private struct if_msghdr2 {
    var ifm_msglen: UInt16 = 0
    var ifm_version: UInt8 = 0
    var ifm_type: UInt8 = 0
    var ifm_addrs: Int32 = 0
    var ifm_flags: Int32 = 0
    var ifm_index: UInt16 = 0
    var ifm_snd_len: Int32 = 0
    var ifm_snd_maxlen: Int32 = 0
    var ifm_snd_drops: Int32 = 0
    var ifm_timer: Int32 = 0
    var ifm_data: if_data64 = if_data64()
}

private struct sockaddr_dl {
    var sdl_len: UInt8 = 0
    var sdl_family: UInt8 = 0
    var sdl_index: UInt16 = 0
    var sdl_type: UInt8 = 0
    var sdl_nlen: UInt8 = 0
    var sdl_alen: UInt8 = 0
    var sdl_slen: UInt8 = 0
    var sdl_data: (Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

// Constants for sysctl
private let CTL_NET: Int32 = 4
private let PF_ROUTE: Int32 = 17
private let NET_RT_IFLIST: Int32 = 3
private let NET_RT_IFLIST2: Int32 = 6
private let RTM_IFINFO: UInt8 = 0xe
private let RTM_IFINFO2: UInt8 = 0x12


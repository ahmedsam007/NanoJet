import Foundation

/// Resolves direct download links from MediaFire and similar file hosting services
public class MediaFireResolver {
    
    /// Resolve a fresh direct download link from a MediaFire page URL
    /// - Parameter pageURL: The MediaFire page URL (e.g., https://www.mediafire.com/file/xxx/filename.ext)
    /// - Returns: A fresh direct download URL if successful, nil otherwise
    public static func resolveDirectURL(from pageURL: URL) async -> URL? {
        // Check if this is a MediaFire URL
        guard let host = pageURL.host?.lowercased(),
              host.contains("mediafire.com") else {
            return nil
        }
        
        do {
            // Fetch the page HTML
            let (data, response) = try await URLSession.shared.data(from: pageURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                DownloadLogger.log(itemId: UUID(), "MediaFireResolver: Failed to fetch page from \(pageURL)")
                return nil
            }
            
            // Extract the direct download link from the HTML
            // MediaFire typically has the download URL in a format like:
            // href="https://download2350.mediafire.com/xxx/filename.ext"
            // or in a JavaScript variable like: 
            // window.location.href = 'https://download.mediafire.com/...'
            
            // Try multiple patterns to find the download link
            let patterns = [
                // Pattern 1: Direct link in href
                #"href="(https?://download[0-9]*\.mediafire\.com/[^"]+)""#,
                // Pattern 2: JavaScript redirect
                #"window\.location\.href\s*=\s*['"]([^'"]+mediafire[^'"]+)['"]"#,
                // Pattern 3: Download button with data attribute
                #"data-href="(https?://[^"]+mediafire[^"]+)""#,
                // Pattern 4: Alternative download link format
                #"aria-label="Download file"\s+href="([^"]+)""#
            ]
            
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
                    for match in matches {
                        if match.numberOfRanges > 1,
                           let range = Range(match.range(at: 1), in: html) {
                            let urlString = String(html[range])
                            // Clean up the URL (remove any escape characters)
                            let cleanURL = urlString
                                .replacingOccurrences(of: "\\", with: "")
                                .replacingOccurrences(of: "&amp;", with: "&")
                            
                            if let downloadURL = URL(string: cleanURL) {
                                DownloadLogger.log(itemId: UUID(), "MediaFireResolver: Extracted download URL: \(downloadURL)")
                                return downloadURL
                            }
                        }
                    }
                }
            }
            
            // Fallback: Look for any download.mediafire.com URL in the page
            if let regex = try? NSRegularExpression(pattern: #"(https?://[^\s"']+download[^\s"']*mediafire[^\s"']+)"#, options: .caseInsensitive) {
                let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
                if let firstMatch = matches.first,
                   firstMatch.numberOfRanges > 1,
                   let range = Range(firstMatch.range(at: 1), in: html) {
                    let urlString = String(html[range])
                        .replacingOccurrences(of: "\\", with: "")
                        .replacingOccurrences(of: "&amp;", with: "&")
                    if let downloadURL = URL(string: urlString) {
                        DownloadLogger.log(itemId: UUID(), "MediaFireResolver: Found fallback download URL: \(downloadURL)")
                        return downloadURL
                    }
                }
            }
            
            DownloadLogger.log(itemId: UUID(), "MediaFireResolver: No download URL found in page")
            return nil
            
        } catch {
            DownloadLogger.log(itemId: UUID(), "MediaFireResolver: Error fetching page: \(error)")
            return nil
        }
    }
    
    /// Check if a URL is from a supported file hosting service
    public static func isSupportedHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let supportedHosts = [
            "mediafire.com",
            "mega.nz",
            "drive.google.com",
            "dropbox.com",
            "wetransfer.com",
            "sendspace.com",
            "zippyshare.com",
            "4shared.com"
        ]
        return supportedHosts.contains { host.contains($0) }
    }
    
    /// Estimate link expiry time based on the service
    public static func estimatedExpiryTime(for url: URL) -> TimeInterval? {
        guard let host = url.host?.lowercased() else { return nil }
        
        // Return expiry time in seconds
        if host.contains("mediafire.com") || host.contains("download") && host.contains("mediafire") {
            return 30 * 60  // 30 minutes
        } else if host.contains("wetransfer.com") {
            return 7 * 24 * 60 * 60  // 7 days
        } else if host.contains("sendspace.com") {
            return 60 * 60  // 1 hour
        }
        
        return nil
    }
}

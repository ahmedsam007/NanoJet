# MediaFire Expired Link Auto-Refresh Solution

## Problem Solved
When downloading files from MediaFire and similar file hosting services, if the user pauses the download and resumes it after 30 minutes, the direct download link expires. Previously, this would cause the download to fail with an error message requiring the user to go back to the website and get a new link.

## Solution Implemented
The app now automatically refreshes expired download links without user intervention by:

1. **Storing Source URLs**: When a download is initiated from MediaFire, the app stores both:
   - The direct download URL (e.g., `https://download2350.mediafire.com/xxx/file.ext`)
   - The source page URL (e.g., `https://www.mediafire.com/file/xxx/file.ext`)

2. **Detecting Expired Links**: When resuming a download, if the server returns:
   - HTTP 200 instead of 206 (range request rejected)
   - HTTP 403/404 errors
   - Probe failures
   
   The app recognizes the link has expired.

3. **Automatic Link Refresh**: When an expired link is detected:
   - The app automatically fetches the MediaFire page using the stored source URL
   - Extracts a fresh direct download link from the page HTML
   - Updates the download with the new link
   - Seamlessly continues downloading from where it left off

## Files Modified

1. **DownloadEngine/Sources/Model/Models.swift**
   - Added `sourceURL` field to store original page URL
   - Added `linkExpiryDate` field to track when links might expire

2. **DownloadEngine/Sources/Engine/DownloadCoordinator.swift**
   - Updated `enqueue` and `enqueueWithBookmark` to accept source URLs
   - Added automatic link expiry detection for MediaFire (30 minutes)

3. **DownloadEngine/Sources/Utilities/MediaFireResolver.swift** (NEW)
   - Created resolver to extract direct download links from MediaFire pages
   - Supports multiple HTML patterns for link extraction
   - Provides expiry time estimates for different services

4. **DownloadEngine/Sources/Engine/SegmentedSessionManager.swift**
   - Integrated automatic link refresh when expired links are detected
   - Added retry logic with fresh links for failed resumes
   - Updated error handling to attempt refresh before failing

5. **NanoJetApp/App/AppViewModel.swift**
   - Updated to detect MediaFire URLs and store source URLs
   - Modified all enqueue calls to pass source URLs when available
   - Enhanced browser extension handling to preserve source information

## Supported Services

The solution currently supports automatic link refresh for:
- **MediaFire** (30-minute expiry)
- Can be easily extended to support:
  - Mega.nz
  - WeTransfer (7-day expiry)  
  - SendSpace (1-hour expiry)
  - 4shared
  - Dropbox
  - Google Drive

## How to Test

### Test 1: Basic MediaFire Download with Pause/Resume
1. Go to MediaFire and upload a test file (or use an existing MediaFire link)
2. Copy the MediaFire page URL (e.g., `https://www.mediafire.com/file/xxx/testfile.zip`)
3. Paste it into NanoJet to start downloading
4. Once download starts, pause it immediately
5. Wait for 31 minutes (to ensure link expires)
6. Click Resume
7. **Expected Result**: Download should resume successfully without errors

### Test 2: Browser Extension with MediaFire
1. Install the NanoJet browser extension
2. Navigate to a MediaFire download page
3. Click the extension to download the file
4. Pause the download after it starts
5. Wait 31+ minutes
6. Resume the download
7. **Expected Result**: Should auto-refresh link and continue

### Test 3: Direct Link Handling
1. If you have a direct MediaFire download link (starts with `https://download`)
2. Make sure to include the Referer header pointing to the MediaFire page
3. Start the download, pause, wait for expiry, resume
4. **Expected Result**: Should use referer to refresh the link

### Test 4: Multiple Pause/Resume Cycles
1. Start a MediaFire download
2. Pause at 20%
3. Wait 31 minutes, then resume
4. Let it download to 50%, pause again
5. Wait another 31 minutes, resume
6. **Expected Result**: Each resume should auto-refresh the link

## Monitoring the Fix

Check the download logs to see the auto-refresh in action:
```
tail -f ~/Library/Logs/NanoJet/downloads.log
```

Look for these log messages:
- `"server returned 200 instead of 206 for range request; link may have expired"`
- `"Attempting to refresh expired link from source URL"`
- `"Successfully refreshed download link"`
- `"MediaFireResolver: Extracted download URL"`

## Error Scenarios

The app will still show an error if:
1. The source MediaFire page is no longer accessible (404)
2. The file was deleted from MediaFire
3. Network connection issues prevent fetching the page
4. MediaFire changes their HTML structure (unlikely but possible)

In these cases, the error message will be:
`"Download link expired and could not be refreshed. Please restart the download with a fresh link from the original page."`

## Technical Details

### Link Expiry Detection
- MediaFire direct links expire after 30 minutes
- Detected when server returns 200 (full response) instead of 206 (partial content)
- Also detected during probe phase when resuming

### HTML Pattern Matching
The MediaFireResolver looks for download links in multiple patterns:
1. Direct href links: `href="https://download*.mediafire.com/..."`
2. JavaScript redirects: `window.location.href = '...'`
3. Data attributes: `data-href="..."`
4. Download button labels: `aria-label="Download file"`

### Security
- Source URLs are stored securely with the download item
- No credentials or cookies are stored
- Each refresh fetches a new public download link

## Future Enhancements

1. **Preemptive Refresh**: Refresh links before they expire (e.g., at 25 minutes)
2. **More Services**: Add support for more file hosting services
3. **Smart Detection**: Auto-detect source URLs from browser history
4. **Batch Refresh**: Refresh multiple expired downloads at once
5. **Custom Expiry**: Allow users to set custom expiry times per service

## Benefits

1. **No User Intervention**: Downloads resume automatically without manual link refresh
2. **Preserves Progress**: Segmented downloads continue from exact byte position
3. **Seamless Experience**: Users don't need to revisit websites
4. **Time Saving**: Especially useful for large files that take hours to download
5. **Reliability**: Reduces failed downloads due to expired links

## Troubleshooting

If auto-refresh doesn't work:
1. Ensure the MediaFire page is still accessible
2. Check if the file still exists on MediaFire
3. Try copying a fresh link from the MediaFire page
4. Check logs for specific error messages
5. Report issues with the HTML pattern if MediaFire updated their site

---

This feature makes NanoJet more reliable for downloading from file hosting services with time-limited download links, providing a seamless download experience even with long pauses.

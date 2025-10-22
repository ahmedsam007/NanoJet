# Download Engine Fixes

## Problem Summary
Two critical issues were fixed:

### Issue A: Pause/Resume Corruption
When pausing and resuming downloads, files were getting corrupted because:

1. **Duplicate tasks on resume** - Old cancelled tasks weren't cleared, causing multiple tasks to write to the same segment simultaneously
2. **Lost progress on pause** - Segment progress wasn't saved when pausing, causing resume to start from stale offsets
3. **Restart on failed probe** - When resuming triggered a server probe that failed, the system would restart from scratch and overwrite partial data

### Issue B: UI Stuck at 0% While Download Progresses
Downloads worked in the background but UI showed "0%" and "Preparing..." status instead of actual progress because:

1. **Race condition on startup** - `ensureQueuedStarted()` was called on every progress update, causing it to see items as "queued" before they transitioned to "downloading"
2. **Status overwrite** - Items that were already downloading got their status reset to `.fetchingMetadata` by the auto-start logic
3. **Duplicate startDownload calls** - The same download was started twice, with the second attempt being ignored but leaving the wrong status

### Issue C: UI Stuck at "Queued" + Duplicate Tasks on Resume
When re-downloading a completed file, the UI would show "Queued" status, and clicking resume created hundreds of duplicate tasks:

1. **Status timing issue** - Item was saved with `.queued` status before `startDownload` was called, creating a window where UI showed "Queued" instead of "Preparing..."
2. **User confusion** - Seeing "Queued", users would click resume multiple times thinking it was stuck
3. **No duplicate protection** - `resumeDownload` didn't check if download was already active, so each resume click created new tasks
4. **Massive duplication** - Multiple resume calls on an already-downloading item created hundreds of duplicate tasks writing to the same segments

## Root Causes Identified from Logs

From your log file, the issues were:

### Issue 1: Duplicate Download Tasks (20:09:10 - 20:09:38)
After the first resume at 20:09:10, you saw hundreds of these:
```
[2025-10-21T20:09:18Z] segment #3 progress: 15095932/15095932 (100.0%)
[2025-10-21T20:09:18Z] segment #3 progress: 15095932/15095932 (100.0%)
[2025-10-21T20:09:18Z] segment #3 progress: 15095932/15095932 (100.0%)
...
```

**Cause:** When pausing, the code cancelled tasks but kept them in the `inflight.tasks` array. On resume, new tasks were added without clearing the old ones, resulting in multiple tasks running simultaneously for the same segment.

### Issue 2: Invalid Server Probe on Resume (20:14:56)
```
[2025-10-21T20:14:56Z] resumeDownload(segmented)
[2025-10-21T20:14:56Z] startDownload(segmented): url=...
[2025-10-21T20:14:58Z] probe HEAD status=200 acceptRanges=false contentLength=0
[2025-10-21T20:15:00Z] probe: supportsRanges=false totalBytes=0
[2025-10-21T20:15:00Z] probe indicates no range support → fallback to single download task
[2025-10-21T20:15:02Z] single-task finalized file: /Users/ahmed/Downloads/ChatGPT_1.2024.317.dmg
```

**Cause:** The resume function called `startDownload` when inflight state was missing. This re-probed the server, which returned invalid data (the MediaFire link may have expired). The system then fell back to single download, which **re-downloaded the entire file and overwrote your 90% completed segmented download**, resulting in corruption.

### Issue 3: Stale Segment Progress
When you paused at 90.4% and resumed, the segments were requesting data from byte 0 instead of from the already-downloaded offset.

**Cause:** The pause function didn't save the current `itemIdToSegmentReceived` values to the item before pausing. When resuming, it used stale progress data from the persisted item.

### Issue 4: UI Stuck at 0% and "Preparing" (Log from second test)
```
[2025-10-21T20:50:08Z] launch segment #1 range=[8770374-17540748] already=0
[2025-10-21T20:50:08Z] startDownload(segmented): url=...
[2025-10-21T20:50:08Z] startDownload ignored: already inflight
[2025-10-21T20:50:09Z] accepted response: seg=#0 range=0-8770373 status=206
[2025-10-21T20:50:09Z] segment #0 progress: 16384/8770374 (0.2%)
[continues downloading successfully to 100%]
```

**Cause:** The `handleProgressUpdate` function in `DownloadCoordinator` was calling `ensureQueuedStarted()` on **every single progress update** (thousands of times per download). This caused a race condition:

1. New item created with status `.queued`
2. First `startDownload` called, begins setting up segments
3. Meanwhile, another download sends a progress update
4. This triggers `ensureQueuedStarted()` which sees the new item is still `.queued`
5. `ensureQueuedStarted()` changes status to `.fetchingMetadata` and calls `startDownload` again
6. Second `startDownload` is ignored (already inflight) but status is now stuck at `.fetchingMetadata`
7. Download works perfectly but UI shows "Preparing..." (fetchingMetadata) instead of "Downloading" with progress

## Fixes Applied

### Fix 1: Clear Tasks on Pause
**File:** `SegmentedSessionManager.swift` line 186-217

```swift
public func pauseDownload(for item: DownloadItem) async {
    if var inflight = itemIdToInflight[itemId] {
        inflight.isCanceled = true
        // Clear all tasks to prevent duplicate task accumulation on resume
        let tasksToCancel = inflight.tasks
        inflight.tasks = []  // ← NEW: Clear the array
        itemIdToInflight[itemId] = inflight
        tasksToCancel.forEach { $0.cancel() }
        // ...
    }
}
```

**Result:** Prevents duplicate tasks from accumulating on multiple pause/resume cycles.

### Fix 2: Save Segment Progress on Pause
**File:** `SegmentedSessionManager.swift` line 196-210

```swift
// Save current segment progress to item BEFORE marking as paused
await updateItem(itemId) { i in
    if var segs = i.segments {
        for idx in segs.indices {
            let segIndex = segs[idx].index
            if let received = self.itemIdToSegmentReceived[itemId]?[segIndex] {
                let need = segs[idx].rangeEnd - segs[idx].rangeStart + 1
                segs[idx].received = min(need, received)
                DownloadLogger.log(itemId: itemId, "pause: saving segment #\(segIndex) progress: \(segs[idx].received)/\(need)")
            }
        }
        i.segments = segs
    }
    i.status = .paused
}
```

**Result:** Ensures accurate progress is saved when pausing, so resume continues from the correct byte offset.

### Fix 3: Reconstruct Inflight State on Resume
**File:** `SegmentedSessionManager.swift` line 237-284

```swift
// If no inflight state exists but item has segments (paused segmented download),
// reconstruct inflight state from persisted item data
if itemIdToInflight[itemId] == nil, let segments = item.segments, !segments.isEmpty, let totalBytes = item.totalBytes {
    DownloadLogger.log(itemId: itemId, "reconstructing inflight state from persisted segments")
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("seg_\(item.id).bin")
    // Verify temp file exists; if not, must restart from scratch
    if !FileManager.default.fileExists(atPath: temp.path) {
        DownloadLogger.log(itemId: itemId, "temp file missing; restarting download")
        await startDownload(for: item)
        return
    }
    let inflight = Inflight(tasks: [], tempFileURL: temp, totalBytes: totalBytes, segments: segments)
    itemIdToInflight[itemId] = inflight
    // ... restore all tracking state ...
    itemIdToSegmentReceived[itemId] = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, $0.received) })
    // Mark this item as having partial segment data (resumed from pause)
    itemIdsWithPartialSegmentData.insert(itemId)
}
```

**Result:** If inflight state is lost (e.g., after app restart), it's reconstructed from persisted data instead of calling `startDownload` which would re-probe the server.

### Fix 4: Prevent Data Overwrite on Failed Probe
**File:** `SegmentedSessionManager.swift` line 80-88

```swift
if !supportsRanges || totalBytes <= 0 {
    // ... YouTube refresh logic ...
    
    // If we have partial segment data, don't overwrite with single download
    if itemIdsWithPartialSegmentData.contains(itemId) {
        DownloadLogger.log(itemId: itemId, "probe failed but partial segment data exists; failing to prevent data loss")
        await updateItem(itemId) { i in
            i.status = .failed
            i.lastError = "Server probe failed (no range support or invalid response). Cannot resume segmented download. The server may have changed the file or the download link may have expired."
        }
        return
    }
    // Fallback: single download using downloadTask so we can pause/resume
    await startSingleDownloadTask(item: item)
    return
}
```

**Result:** If a server probe fails during resume and we have partial segmented data, the download **fails safely** instead of overwriting your progress with a fresh single download.

### Fix 5: Only Auto-Start Queued Items When Necessary
**File:** `DownloadCoordinator.swift` line 102-110

```swift
public func handleProgressUpdate(_ updated: DownloadItem) async {
    items[updated.id] = updated
    await save()
    NotificationCenter.default.post(name: .downloadItemsDidChange, object: nil)
    // Auto-start queued items only when an item completes or fails (not on every progress update)
    if updated.status == .completed || updated.status == .failed || updated.status == .canceled {
        await ensureQueuedStarted()
    }
}
```

**Changes:**
- Previously: `ensureQueuedStarted()` was called on **every progress update** (thousands of times per download)
- Now: Only called when a download completes, fails, or is canceled

**Also updated:** `restoreFromDisk()` at line 113-123
```swift
public func restoreFromDisk() async {
    do {
        let loaded = try await persistence.load()
        items = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        NotificationCenter.default.post(name: .downloadItemsDidChange, object: nil)
        // Auto-start any queued items from previous session
        await ensureQueuedStarted()
    } catch {
        print("Failed to load downloads: \(error)")
    }
}
```

**Result:** 
- Eliminates the race condition that caused status to be stuck at `.fetchingMetadata`
- UI now correctly shows "Downloading" with real-time progress percentages
- No more duplicate `startDownload` calls in logs
- Much better performance (not calling expensive auto-start logic thousands of times)
- Queued items still auto-start properly when app loads or when a download finishes

### Fix 6: Set Initial Status to Preparing
**File:** `DownloadCoordinator.swift` line 27-37

```swift
@discardableResult
public func enqueue(url: URL, suggestedFileName: String? = nil, headers: [String: String]? = nil) async -> DownloadItem {
    var item = DownloadItem(url: url, finalFileName: suggestedFileName)
    item.requestHeaders = headers
    // Set status to fetchingMetadata so UI shows "Preparing..." instead of "Queued"
    // This prevents users from clicking resume before startDownload completes
    item.status = .fetchingMetadata
    items[item.id] = item
    await save()
    NotificationCenter.default.post(name: .downloadItemsDidChange, object: nil)
    await sessionManager.startDownload(for: item)
    return item
}
```

**Changes:**
- Previously: Item started with `.queued` status, saved, then `startDownload` called
- Now: Item starts with `.fetchingMetadata` status before being saved
- Explicit notification sent to update UI immediately

**Result:**
- UI shows "Preparing..." immediately instead of "Queued"
- Users understand something is happening and won't click resume
- Eliminates the window where status appears stuck at "Queued"

### Fix 7: Prevent Duplicate Resume Calls
**File:** `SegmentedSessionManager.swift` line 247-258

```swift
public func resumeDownload(for item: DownloadItem) async {
    let itemId = item.id
    DownloadLogger.log(itemId: itemId, "resumeDownload(segmented)")
    
    // Prevent duplicate resume calls: if already downloading, ignore
    if let existing = itemIdToInflight[itemId], !existing.isCanceled, !existing.isFinalized {
        let hasActiveTasks = !existing.tasks.isEmpty
        if hasActiveTasks {
            DownloadLogger.log(itemId: itemId, "resumeDownload ignored: already downloading with active tasks")
            return
        }
    }
    
    // Resume fallback single download if we have resume data
    // ... rest of function
}
```

**Changes:**
- Added guard at the beginning of `resumeDownload`
- Checks if download is already active with tasks running
- Returns early if duplicate resume attempt detected

**Result:**
- Multiple resume button clicks are harmless - only the first one works
- No more duplicate tasks created when user clicks resume multiple times
- Logs will show "resumeDownload ignored" instead of creating duplicates
- Prevents the hundreds of "100%" progress messages from duplicate tasks

## Testing Recommendations

1. **Test UI updates (Issue B fix):**
   - Start a new download
   - UI should immediately show "Downloading" status (not stuck on "Preparing")
   - Progress percentage should update in real-time from 0% to 100%
   - Check log file - should see only ONE `startDownload` call per download
   - No "startDownload ignored: already inflight" messages

2. **Test pause/resume cycles (Issue A fix):**
   - Start a large download (>50MB)
   - Pause at ~30%
   - Resume and let it download to ~60%
   - Pause again
   - Resume and let it complete
   - Verify file integrity (the app computes SHA-256 hash on completion)
   - Check log - should see "pause: saving segment #X progress" messages

3. **Test network interruption:**
   - Start a download
   - Disconnect WiFi during download
   - Reconnect WiFi
   - Verify download resumes from correct offset
   - No duplicate progress messages in log

4. **Test expired links:**
   - Start a download from MediaFire/temporary link
   - Pause it
   - Wait for link to expire (or manually change the URL in downloads.json)
   - Resume
   - Should fail with clear error message, not corrupt the file

5. **Test multiple concurrent downloads:**
   - Start 3-4 downloads simultaneously
   - All should show correct progress immediately
   - No status overwrites or "stuck at 0%" issues

6. **Test re-downloading same file (Issue C fix):**
   - Download a file completely
   - Paste the same URL again to re-download
   - Should immediately show "Preparing..." then "Downloading"
   - Should NOT show "Queued" at any point
   - Try clicking resume button multiple times rapidly
   - Check log - should see "resumeDownload ignored: already downloading with active tasks"
   - Should NOT see hundreds of duplicate "100%" messages
   - Download should complete successfully without corruption

## Additional Changes

### Allow Duplicate Downloads
The app now allows downloading the same URL multiple times simultaneously. This is useful for:
- Re-downloading updated versions of files
- Downloading the same file to different locations
- Testing download behavior

**Files changed:**
- `ContentView.swift` (line 744): Always passes `allowDuplicate: true` when submitting URLs
- `IDMMacApp.swift` (line 39): Browser extension downloads now allow duplicates
- `AppViewModel.swift` (line 350): Clipboard downloads now allow duplicates

Previously, the app would show a "Duplicate Download" warning if you tried to download a URL that was already queued or downloading. Now it allows multiple concurrent downloads of the same URL without any warnings.

## Additional Notes

- The fix adds a new tracking set `itemIdsWithPartialSegmentData` to know which downloads have segment data that must be protected
- All cleanup is done in `tryFinalizeIfComplete` and `cancelDownload` to ensure flags are cleared properly
- The fix is backward-compatible with existing downloads in progress

## What to Watch For

After these fixes, your logs should show:

**For UI Updates (Issue B):**
- ✅ Only **one** `startDownload` call per download (not two)
- ✅ No "startDownload ignored: already inflight" messages
- ✅ Status goes directly from queued → downloading (not stuck at fetchingMetadata)
- ✅ UI shows real-time progress from 0% to 100%

**For Pause/Resume (Issue A):**
- ✅ "pause: saving segment #X progress" messages when you click pause
- ✅ **No duplicate progress messages** after resume (no hundreds of "100%" lines)
- ✅ **Correct byte ranges** in "accepted response" messages after resume (starting from where you paused, not from 0)
- ✅ If you resume after pausing at 60%, segments should request ranges starting at ~60%, not 0
- ✅ **Clear error messages** if a link expires instead of silent corruption

**For Re-downloading / Duplicate Resume (Issue C):**
- ✅ New downloads show "Preparing..." immediately, never stuck at "Queued"
- ✅ Clicking resume multiple times shows "resumeDownload ignored: already downloading with active tasks"
- ✅ No hundreds of duplicate "100%" messages even if you spam the resume button
- ✅ Downloads complete successfully without corruption

**Special Messages:**
- `probe failed but partial segment data exists; failing to prevent data loss` - the download link has expired. Remove the download and start fresh with a new link.
- `reconstructing inflight state from persisted segments` - the app is recovering from a restart and properly resuming your download.
- `resumeDownload ignored: already downloading with active tasks` - you clicked resume on an already-downloading item; this is normal and prevents duplicate tasks.
- `startDownload ignored: already inflight` - should NOT appear anymore (this was the bug causing duplicate tasks).


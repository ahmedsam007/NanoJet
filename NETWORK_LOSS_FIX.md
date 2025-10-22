# Network Loss Download Corruption Fix

## Problem Description

When internet connection was lost during a download and then resumed, the app would complete the download but produce a corrupted file that couldn't be opened. The log showed:

```
[2025-10-21T11:03:25Z] rejecting response: content-range start=26198016 expected=0 seg=#0
```

The server was sending data from the wrong byte position after network reconnection, but the app continued anyway and finalized a corrupted file.

## Root Causes

1. **No segment progress reset on range mismatch**: When the server returned data from the wrong position, the app rejected it but didn't reset the segment's progress counter
2. **Missing expectedStart tracking in retry logic**: The retry mechanism didn't properly update the expected byte position
3. **No file integrity validation**: The app would finalize files even if the size didn't match expectations
4. **Infinite retry on range mismatches**: The app would keep retrying indefinitely even when the server consistently returned wrong byte ranges

## Fixes Implemented

### 1. Range Rejection Tracking & Progress Reset
- Added `itemIdToRangeRejectCounts` dictionary to track how many times each segment has received wrong byte ranges
- When a range mismatch is detected:
  - The segment's received bytes counter is **reset to 0**
  - The rejection count is incremented
  - If rejections exceed 3 attempts, the download **fails** with a clear error message

```swift
// Reset segment progress to prevent data corruption
DownloadLogger.log(itemId: itemId, "resetting segment #\(segIndex) progress due to range mismatch")
itemIdToSegmentReceived[itemId]?[segIndex] = 0

// Fail after too many rejections
if rejectCount >= maxRangeRejectsPerSegment {
    item.status = .failed
    item.lastError = "Server does not properly support resume. Range mismatch after \(rejectCount) attempts"
}
```

### 2. Fixed Retry Logic
Updated the automatic retry mechanism to properly set `taskIdToExpectedStart` so subsequent range validation works correctly:

```swift
self.taskIdToExpectedStart[retryTask.taskIdentifier] = seg.rangeStart + got
```

### 3. File Size Validation Before Finalization
Added integrity check before moving the temp file to Downloads:

```swift
if fileSize != inflight.totalBytes {
    item.status = .failed
    item.lastError = "File size mismatch: expected \(inflight.totalBytes) bytes but got \(fileSize) bytes"
    return
}
```

### 4. Proper State Cleanup
Added cleanup of the new `itemIdToRangeRejectCounts` dictionary when downloads complete.

## Expected Behavior After Fix

### Scenario 1: Network loss with good server support
1. Connection lost at 85% complete
2. Connection restored
3. Server sends correct byte ranges
4. Download resumes from 85% and completes successfully ✅

### Scenario 2: Network loss with broken server support
1. Connection lost at 85% complete
2. Connection restored
3. Server sends wrong byte range (e.g., starts from 0 instead of continuing)
4. App detects mismatch, resets segment progress, and retries
5. After 3 failed attempts, download **fails** with clear error message ✅
6. User can see the error: "Server does not properly support resume"

### Scenario 3: Corrupted data detected
1. All segments report complete
2. File size doesn't match expected total
3. Download **fails** with error: "File size mismatch - file may be corrupted" ✅
4. Corrupted file is NOT moved to Downloads folder

## Testing Recommendations

### Test Case 1: Mediafire with Network Interruption
1. Start downloading a large file from Mediafire (like in your log)
2. Turn off WiFi/disconnect network after ~50% progress
3. Wait 30 seconds
4. Reconnect network
5. **Expected**: Download should resume successfully or fail gracefully (no corruption)

### Test Case 2: Simulated Bad Server
If you can test with a server that doesn't properly support resume:
1. Start download
2. Interrupt it
3. Resume
4. **Expected**: After 3 range mismatches, download fails with helpful error message

### Test Case 3: Large File Completion
1. Download a large file (100MB+) completely with several network interruptions
2. Verify the final file opens correctly
3. Compare file size with expected size

## Log Messages to Watch For

After this fix, you should see in logs:
- `resetting segment #X progress due to range mismatch (reject count: Y)`
- `segment #X exceeded max range rejections (3) → failing download`
- `finalize aborted: file size mismatch (expected=X actual=Y)`

## Files Modified

- `DownloadEngine/Sources/Engine/SegmentedSessionManager.swift`
  - Added range rejection tracking (lines 34-35)
  - Enhanced range validation logic (lines 608-639)
  - Added file size validation before finalization (lines 485-509)
  - Fixed retry logic to update expectedStart (line 846)
  - Added cleanup of rejection counters (line 543)

## Migration Notes

This fix is **backward compatible** - existing downloads will automatically get the new protection when they resume.

No user data or settings changes required.


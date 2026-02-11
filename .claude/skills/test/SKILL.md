---
name: test
description: Run tests for the watchOS app and iOS app and display a filtered report
---

# Test

Run tests for both the watchOS app and iOS app and analyze the results.

## Steps

1. Delete any existing result bundles in the project root:
   ```
   rm -rf TestResults.xcresult TestResults-iOS.xcresult
   ```
2. Shut down any running simulators, then run watchOS tests with coverage enabled and max 2 parallel workers (3+ clones cause spurious launch failures on watchOS):
   ```
   xcrun simctl shutdown all 2>/dev/null
   xcodebuild test -project beschluenige.xcodeproj -scheme "beschluenige Watch App" -destination 'platform=watchOS
      Simulator,name=Apple Watch Ultra 3 (49mm)' -enableCodeCoverage YES -resultBundlePath ./TestResults.xcresult -maximum-parallel-testing-workers 2 >/tmp/test.out 2>&1
   ```
3. Run iOS tests (1 worker to avoid shared-singleton issues with WatchConnectivityManager.shared):
   ```
   xcodebuild test -project beschluenige.xcodeproj -scheme "beschluenige" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -enableCodeCoverage YES -resultBundlePath ./TestResults-iOS.xcresult -maximum-parallel-testing-workers 1 >/tmp/test-ios.out 2>&1
   ```
4. Analyse results using `grep` or `tail` on both `/tmp/test.out` and `/tmp/test-ios.out`.
   - Show any build errors to the user
   - Show any failed tests to the user
   - Don't immediately assume a failed test is "flaky", try to figure out why it failed.

---
name: test 
description: Run tests for the watchOS app and display a filtered report
---

# Test 

Run tests for the watchOS app and analyze the results.

## Steps

1. Delete any existing `TestResults.xcresult` in the project root:
   ```
   rm -rf TestResults.xcresult
   ```
2. Shut down any running simulators, then run watchOS tests with coverage enabled and max 2 parallel workers (3+ clones cause spurious launch failures on watchOS):
   ```
   xcrun simctl shutdown all 2>/dev/null
   xcodebuild test -project beschluenige.xcodeproj -scheme "beschluenige Watch App" -destination 'platform=watchOS
      Simulator,name=Apple Watch Ultra 3 (49mm)' -enableCodeCoverage YES -resultBundlePath ./TestResults.xcresult -maximum-parallel-testing-workers 2 >/tmp/test.out 2>&1
   ```
3. Analyse results using `grep` or `tail`.
   - Show any build errors to the user
   - Show any failed tests to the user
   - Don't immediately assume a failed test is "flaky", try to figure out why it failed.

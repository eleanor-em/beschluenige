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
2. Run watchOS tests with coverage enabled:
   ```
   xcodebuild test -project beschluenige.xcodeproj -scheme "beschluenige Watch App" -destination 'platform=watchOS
      Simulator,name=Apple Watch Ultra 3 (49mm)' -enableCodeCoverage YES -resultBundlePath ./TestResults.xcresult >/tmp/test.out 2>&1
   ```
3. Analyse results using `grep` or `tail`.
   - Show any build errors to the user
   - Show any failed tests to the user
   - Don't immediately assume a failed test is "flaky", try to figure out why it failed.

---
name: coverage
description: Run test coverage for the watchOS app and display a filtered report
---

# Coverage

Run test coverage for the watchOS app and display a filtered report.

## Steps

1. Delete any existing `TestResults.xcresult` in the project root:
   ```
   rm -rf TestResults.xcresult
   ```
2. Run tests with coverage enabled:
   ```
   xcodebuild test -project beschluenige.xcodeproj -scheme "beschluenige Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)' -enableCodeCoverage YES -resultBundlePath -maximum-parallel-testing-workers 2 ./TestResults.xcresult 2>&1 > /tmp/out.log
   ```
3. Generate the filtered coverage report. The filtered files are a workaround for limitations of xccov. No other files should ever be added.
   ```
   xcrun xccov view --report TestResults.xcresult | grep ".swift" | grep -v "Util/Assertions.swift" | grep -v "ConnectivitySession.swift" | grep -v "AppTests/"
   ```
4. When presenting the report to the user:
   - Summarise per-file coverage for the watch app in a markdown table.
   - Highlight any files below 100% coverage. YOU MUST ACHIEVE 100% COVERAGE FOR ALL FILES.

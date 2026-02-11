---
name: coverage
description: Run test coverage for the watchOS app and iOS app and display a filtered report
---

# Coverage

Run test coverage for both the watchOS app and iOS app and display a filtered report.

## Steps

1. Delete any existing result bundles in the project root:
   ```
   rm -rf TestResults.xcresult TestResults-iOS.xcresult
   ```
2. Run watchOS tests with coverage enabled:
   ```
   xcodebuild test -project beschluenige.xcodeproj -scheme "beschluenige Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)' -enableCodeCoverage YES -resultBundlePath ./TestResults.xcresult -maximum-parallel-testing-workers 2 >/tmp/coverage.out 2>&1
   ```
3. Run iOS tests with coverage enabled (1 worker to avoid shared-singleton issues):
   ```
   xcodebuild test -project beschluenige.xcodeproj -scheme "beschluenige" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -enableCodeCoverage YES -resultBundlePath ./TestResults-iOS.xcresult -maximum-parallel-testing-workers 1 >/tmp/coverage-ios.out 2>&1
   ```
4. Generate the filtered coverage reports. The filtered files are a workaround for limitations of xccov. No other files should ever be added.
   ```
   xcrun xccov view --report TestResults.xcresult | grep ".swift" | grep -v "Util/Assertions.swift" | grep -v "ConnectivitySession.swift" | grep -v "Tests/" | grep -v "UITests/"
   ```
   ```
   xcrun xccov view --report TestResults-iOS.xcresult | grep ".swift" | grep -v "Tests/"
   ```
5. When presenting the report to the user:
   - Summarise per-file coverage for both the watch app and the iOS app in separate markdown tables.
   - Highlight any files below 100% coverage. YOU MUST ACHIEVE 100% COVERAGE FOR ALL FILES.

---
name: lint
description: Run SwiftLint to fix, format, and report remaining issues
---

# Lint

Run SwiftLint with auto-fix and formatting, then report any remaining violations.

## Steps

1. Run SwiftLint with `--fix --format` to auto-correct fixable violations and reformat:
   ```
   swiftlint lint --fix --format 2>&1
   ```
2. Run SwiftLint again (without `--fix`) to report any remaining violations:
   ```
   swiftlint lint 2>&1
   ```
3. When presenting results to the user:
   - If auto-fix corrected any files, list which files were modified.
   - Show any remaining warnings or errors in a concise table.
   - If there are no remaining violations, confirm a clean bill of health.

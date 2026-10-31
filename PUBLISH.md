# Publishing to pub.dev (160/160)

pub.dev scores packages across 5 sections. All must be clean before publishing.

---

## 1. Dart file conventions (30/30)

### pubspec.yaml
- `name`, `description`, `version`, `repository` must all be present.
- `description` must be between 60–180 characters.
- Version must match the latest entry in `CHANGELOG.md`.

### CHANGELOG.md
- Must exist and follow the format `## x.y.z` for the latest version.

### README.md
- Must exist and not be empty.

### License
- Must use an [OSI-approved license](https://opensource.org/licenses). BSD-3-Clause is fine.

---

## 2. Documentation (20/20)

### Dartdoc coverage
At least **20% of public API elements** must have dartdoc comments. Aim for as high as possible.

Run to check for warnings:
```sh
dart doc
```

All `warning: unresolved doc reference [...]` must be fixed before publishing.

**Common fixes:**
- If a symbol is not exported from the public library, replace `[SymbolName]` with `` `SymbolName` `` in the comment.
- If a symbol is exported, ensure the reference spelling exactly matches the class/method name.

### Example
- The `example/` folder must contain a runnable Flutter/Dart example.

---

## 3. Platform support (20/20)

No action needed if the package has no platform-specific code. Pure Dart / Flutter packages automatically support all 6 platforms (iOS, Android, Web, Windows, macOS, Linux).

---

## 4. Static analysis (50/50)

```sh
dart analyze lib/
```

Must produce **zero errors, warnings, lints, or formatting issues**.

### Formatting
```sh
# Check (dry run)
dart format --output=none --set-exit-if-changed lib/ test/

# Fix
dart format lib/ test/
```

Run `dart format` after every significant change. The pub.dev scorer will fail the entire static analysis section if any file is not formatted.

---

## 5. Up-to-date dependencies (40/40)

```sh
dart pub outdated
```

Constraints must be compatible with the latest stable versions. Adjust lower bounds in `pubspec.yaml` if needed.

---

## Pre-publish checklist

Run these commands from `packages/tanstack_query/` in order:

```sh
# 1. Format
dart format lib/ test/

# 2. Static analysis — must be 0 errors, 0 warnings
dart analyze lib/

# 3. Tests — must all pass
flutter test

# 4. Doc check — must be 0 warnings, 0 errors
dart doc

# 5. Dry-run publish (validates pubspec, files, etc.)
dart pub publish --dry-run
```

Only proceed to publish if every step above exits cleanly.

---

## Publish

```sh
dart pub publish
```

You will be prompted to confirm. The package will be live on pub.dev within a few minutes.

> **Note:** pub.dev rescores automatically after publish. Scores are cached; allow up to 30 minutes for the full score to appear.

---

## Versioning convention

| Change type | Example |
|---|---|
| Breaking change | `1.x.0` → `2.0.0` |
| New feature (non-breaking) | `1.2.x` → `1.3.0` |
| Bug fix / patch | `1.2.5` → `1.2.6` |

Always update **both** `pubspec.yaml` and `CHANGELOG.md` to the same version before publishing.

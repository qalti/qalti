# Qalti Developer Setup (Clean Machine)

This guide is for external developers who see this project for the first time and need to build and run it from source on macOS.

## Route Decision

- Need a quick product check and no source changes: use **Route A** in `README.md` (install prebuilt app and run from UI).
- Need to modify code or contribute: use this guide (**Route B**, source build).

## Preflight Checklist

Run these checks from a terminal before building:

```bash
xcodebuild -version
xcode-select -p
xcrun simctl list devices available
```

Expected baseline:

- macOS with Xcode **16.4+**
- iOS Simulator runtime installed
- at least one available simulator device

If the wrong Xcode is selected:

```bash
sudo xcode-select -s /Applications/Xcode-16.4.app/Contents/Developer
```

## Step 1: Generate Simulator Runner Artifacts

From repo root:

```bash
cd xcodeproject
bash ./scripts/archive_simulator_runner.sh
cd ..
```

Done checkpoint:

- `xcodeproject/.artifacts/simulator-runner/qalti-runner-simulator.tar.bz2` exists
- script output shows both `QaltiRunner.app` and `QaltiUITests-Runner.app` copied

## Step 2: Build Qalti macOS App from Source

From repo root:

```bash
xcodebuild \
  -project xcodeproject/Qalti.xcodeproj \
  -scheme Qalti \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath xcodeproject/DerivedData_local \
  build
```

Done checkpoint:

- `xcodeproject/DerivedData_local/Build/Products/Debug/Qalti.app` exists

## Step 3: Launch and Verify Binary Paths

Launch the built app:

```bash
open xcodeproject/DerivedData_local/Build/Products/Debug/Qalti.app
```

Verify CLI binaries from the same build output:

```bash
xcodeproject/DerivedData_local/Build/Products/Debug/Qalti.app/Contents/MacOS/Qalti cli --help
xcodeproject/DerivedData_local/Build/Products/Debug/Qalti.app/Contents/Resources/QaltiScheduler --help
```

## Step 4: Run a First CLI Test (Optional)

This step requires your OpenRouter API key and a simulator app build.

1) Create or copy your OpenRouter API key from https://openrouter.ai/keys
2) Download demo app build (SyncUps):

```bash
curl -L -o SyncUps-simulator.zip https://app.qalti.com/SyncUps/SyncUps-simulator.zip
```

3) Export `OPENROUTER_API_KEY` and run a sample test:

```bash
export OPENROUTER_API_KEY="sk-or-v1-..."
xcodeproject/DerivedData_local/Build/Products/Debug/Qalti.app/Contents/MacOS/Qalti \
  cli ./tests/syncups_change_theme.test \
  --app-path ./SyncUps-simulator.zip \
  --device-name "iPhone 16"
```

Done checkpoint:

- test execution starts and prints step-by-step run output

## When to Rebuild Simulator Runner Artifacts

Re-run `xcodeproject/scripts/archive_simulator_runner.sh` when you change:

- `QaltiRunner`
- `QaltiRunnerLib`
- `QaltiUITests`

You usually do not need to re-run it when changing only the main macOS app target.

## Troubleshooting

- Wrong Xcode version in builds:
  - run `xcode-select -p`
  - switch with `sudo xcode-select -s /Applications/Xcode-16.4.app/Contents/Developer`

- No available simulator device/runtime:
  - install iOS runtime in Xcode
  - create a simulator device
  - re-check with `xcrun simctl list devices available`

- Build fails because runner payload is missing:
  - re-run `bash xcodeproject/scripts/archive_simulator_runner.sh`

- CLI run fails with auth/token errors:
  - ensure `OPENROUTER_API_KEY` is set in your shell
  - or pass it explicitly: `--token <OPENROUTER_API_KEY>`

- Real-device run fails due to signing:
  - start with simulator route first
  - use CI keychain/signing setup from `scripts/setup_runner.sh` as reference

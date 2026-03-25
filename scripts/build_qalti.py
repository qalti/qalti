#!/usr/bin/env python3
"""
Qalti Build Script
Automates the build process described in DEVELOPER.md

Enhanced version with:
- Automatic build tool installation
- Optional derived data cleaning
- Better error handling and guidance
"""

import subprocess
import sys
import os
import shutil
import argparse
from pathlib import Path


class Colors:
    """ANSI color codes for terminal output"""

    HEADER = "\033[95m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    ENDC = "\033[0m"
    BOLD = "\033[1m"


def print_step(step_num, title, description=""):
    """Print a formatted step header"""
    print(f"\n{Colors.HEADER}{'='*60}{Colors.ENDC}")
    print(f"{Colors.BOLD}Step {step_num}: {title}{Colors.ENDC}")
    if description:
        print(f"{Colors.CYAN}{description}{Colors.ENDC}")
    print(f"{Colors.HEADER}{'='*60}{Colors.ENDC}\n")


def run_command(cmd, description="", check=True, capture_output=False):
    """Run a shell command with formatted output"""
    print(f"{Colors.BLUE}Running: {cmd}{Colors.ENDC}")
    if description:
        print(f"{Colors.CYAN}{description}{Colors.ENDC}")

    try:
        if capture_output:
            result = subprocess.run(
                cmd, shell=True, check=check, capture_output=True, text=True
            )
            return result
        else:
            result = subprocess.run(cmd, shell=True, check=check)
            return result
    except subprocess.CalledProcessError as e:
        print(f"{Colors.RED}Error running command: {cmd}{Colors.ENDC}")
        print(f"{Colors.RED}Exit code: {e.returncode}{Colors.ENDC}")
        if capture_output and e.stderr:
            print(f"{Colors.RED}Error output: {e.stderr}{Colors.ENDC}")
        raise


def check_file_exists(filepath, description=""):
    """Check if a file exists and print status"""
    path = Path(filepath)
    if path.exists():
        print(f"{Colors.GREEN}✓ {description or filepath} exists{Colors.ENDC}")
        return True
    else:
        print(f"{Colors.RED}✗ {description or filepath} missing{Colors.ENDC}")
        return False


def preflight_checks():
    """Run preflight checks as described in DEVELOPER.md"""
    print_step(0, "Preflight Checks", "Verifying system requirements and tools")

    # Check xcodebuild version
    try:
        result = run_command("xcodebuild -version", capture_output=True)
        print(f"{Colors.GREEN}Xcode version:{Colors.ENDC}")
        print(result.stdout)
    except subprocess.CalledProcessError:
        print(f"{Colors.RED}Error: xcodebuild not found or failed{Colors.ENDC}")
        return False

    # Check xcode-select path
    try:
        result = run_command("xcode-select -p", capture_output=True)
        print(
            f"{Colors.GREEN}Developer directory: {result.stdout.strip()}{Colors.ENDC}"
        )
    except subprocess.CalledProcessError:
        print(f"{Colors.RED}Error: xcode-select failed{Colors.ENDC}")
        return False

    # Check and install build formatting tools
    print(f"{Colors.CYAN}Checking build formatting tools...{Colors.ENDC}")

    # Check xcbeautify (preferred)
    try:
        run_command("command -v xcbeautify", capture_output=True)
        print(f"{Colors.GREEN}✓ xcbeautify found{Colors.ENDC}")
    except subprocess.CalledProcessError:
        # Check xcpretty as fallback
        try:
            run_command("xcpretty --version", capture_output=True)
            print(f"{Colors.GREEN}✓ xcpretty found{Colors.ENDC}")
        except subprocess.CalledProcessError:
            print(f"{Colors.YELLOW}⚠️  No build formatting tools found{Colors.ENDC}")
            print(f"{Colors.CYAN}Installing xcpretty...{Colors.ENDC}")
            try:
                run_command("gem install xcpretty", "Installing xcpretty gem")
                print(f"{Colors.GREEN}✓ xcpretty installed successfully{Colors.ENDC}")
            except subprocess.CalledProcessError:
                print(f"{Colors.RED}✗ Failed to install xcpretty{Colors.ENDC}")
                print(
                    f"{Colors.YELLOW}Build will continue with plain output.{Colors.ENDC}"
                )
                print(
                    f"{Colors.CYAN}To fix this later, run: make fix-tools{Colors.ENDC}"
                )
                # Don't fail the build, just warn

    # Check available simulators
    try:
        result = run_command("xcrun simctl list devices available", capture_output=True)
        print(f"{Colors.GREEN}Available simulator devices:{Colors.ENDC}")
        # Print only first 20 lines to avoid too much output
        lines = result.stdout.split("\n")[:20]
        print("\n".join(lines))
        if len(result.stdout.split("\n")) > 20:
            print("... (output truncated)")
    except subprocess.CalledProcessError:
        print(f"{Colors.RED}Error: xcrun simctl failed{Colors.ENDC}")
        return False

    return True


def generate_simulator_artifacts():
    """Generate simulator runner artifacts"""
    print_step(
        1,
        "Generate Simulator Runner Artifacts",
        "Building QaltiRunner and QaltiUITests artifacts",
    )

    # Change to xcodeproject directory
    original_dir = os.getcwd()
    try:
        os.chdir("xcodeproject")

        # Run the archive script
        run_command(
            "bash ./scripts/archive_simulator_runner.sh",
            "Creating simulator runner archive",
        )

        # Check if artifact was created
        artifact_path = ".artifacts/simulator-runner/qalti-runner-simulator.tar.bz2"
        if check_file_exists(artifact_path, "Simulator runner artifact"):
            print(f"{Colors.GREEN}✓ Step 1 completed successfully{Colors.ENDC}")
            return True
        else:
            print(f"{Colors.RED}✗ Step 1 failed: artifact not created{Colors.ENDC}")
            return False

    finally:
        os.chdir(original_dir)


def build_macos_app(clean_derived_data=True):
    """Build the macOS app using xcodebuild"""
    print_step(2, "Build Qalti macOS App", "Building from source using xcodebuild")

    derived_data_path = "xcodeproject/DerivedData_local"

    # Conditionally clean DerivedData
    if clean_derived_data and os.path.exists(derived_data_path):
        print(
            f"{Colors.YELLOW}Removing existing DerivedData (use --no-clean to skip)...{Colors.ENDC}"
        )
        shutil.rmtree(derived_data_path)
    elif not clean_derived_data and os.path.exists(derived_data_path):
        print(
            f"{Colors.CYAN}Keeping existing DerivedData for fast incremental build...{Colors.ENDC}"
        )
    elif not os.path.exists(derived_data_path):
        print(
            f"{Colors.CYAN}DerivedData directory will be created during build...{Colors.ENDC}"
        )

    # Set environment variables for build tools
    env = os.environ.copy()
    env["LANG"] = "en_US.UTF-8"
    env["LC_ALL"] = "en_US.UTF-8"

    # Build command from DEVELOPER.md
    build_cmd = """xcodebuild \\
  -project xcodeproject/Qalti.xcodeproj \\
  -scheme Qalti \\
  -configuration Debug \\
  -destination "platform=macOS" \\
  -derivedDataPath xcodeproject/DerivedData_local \\
  build"""

    print(f"{Colors.CYAN}Setting UTF-8 locale for build tools...{Colors.ENDC}")

    # Run build with proper environment
    try:
        subprocess.run(build_cmd, shell=True, check=True, env=env)
        print(f"{Colors.GREEN}Build completed successfully{Colors.ENDC}")
    except subprocess.CalledProcessError as e:
        print(f"{Colors.RED}Build failed with exit code {e.returncode}{Colors.ENDC}")
        print(
            f"{Colors.YELLOW}If this is due to missing build tools, "
            f"try: make fix-tools{Colors.ENDC}"
        )
        raise

    # Check if app was built
    app_path = "xcodeproject/DerivedData_local/Build/Products/Debug/Qalti.app"
    if check_file_exists(app_path, "Built Qalti.app"):
        print(f"{Colors.GREEN}✓ Step 2 completed successfully{Colors.ENDC}")
        return True
    else:
        print(f"{Colors.RED}✗ Step 2 failed: app not built{Colors.ENDC}")
        return False


def verify_binaries():
    """Verify the built binaries"""
    print_step(3, "Verify Binary Paths", "Checking CLI binaries from build output")

    app_path = "xcodeproject/DerivedData_local/Build/Products/Debug/Qalti.app"
    qalti_binary = f"{app_path}/Contents/MacOS/Qalti"
    scheduler_binary = f"{app_path}/Contents/Resources/QaltiScheduler"

    # Check if binaries exist
    if not check_file_exists(qalti_binary, "Qalti CLI binary"):
        return False

    if not check_file_exists(scheduler_binary, "QaltiScheduler binary"):
        return False

    # Test CLI help commands
    try:
        run_command(
            f"{qalti_binary} cli --help", "Testing Qalti CLI help", capture_output=True
        )
        print(f"{Colors.GREEN}✓ Qalti CLI help works{Colors.ENDC}")
    except subprocess.CalledProcessError:
        print(f"{Colors.RED}✗ Qalti CLI help failed{Colors.ENDC}")
        return False

    try:
        run_command(
            f"{scheduler_binary} --help",
            "Testing QaltiScheduler help",
            capture_output=True,
        )
        print(f"{Colors.GREEN}✓ QaltiScheduler help works{Colors.ENDC}")
    except subprocess.CalledProcessError:
        print(f"{Colors.RED}✗ QaltiScheduler help failed{Colors.ENDC}")
        return False

    print(f"{Colors.GREEN}✓ Step 3 completed successfully{Colors.ENDC}")
    return True


def launch_app(is_first_launch=False):
    """Launch the built app with appropriate guidance for first launch"""
    step_desc = "Opening the built Qalti.app"
    if is_first_launch:
        step_desc = "First Launch - Opening Qalti.app (permission setup)"

    print_step(4, "Launch App", step_desc)

    app_path = "xcodeproject/DerivedData_local/Build/Products/Debug/Qalti.app"

    if is_first_launch:
        print(f"{Colors.YELLOW}🚨 FIRST LAUNCH - EXPECTED BEHAVIOR:{Colors.ENDC}")
        print(
            f"{Colors.CYAN}1. App will request folder access permissions{Colors.ENDC}"
        )
        print(
            f"{Colors.CYAN}2. Click 'Allow' when prompted for"
            f" Downloads, Documents, Desktop{Colors.ENDC}"
        )
        print(
            f"{Colors.YELLOW}3. ⚠️  Left panel may appear EMPTY initially"
            f" (this is normal!){Colors.ENDC}"
        )
        print(
            f"{Colors.CYAN}4. Close the app and relaunch it to see folders properly"
            f"{Colors.ENDC}"
        )
        print(
            f"{Colors.GREEN}5. Second launch will show files/folders"
            f" and 'Create your first test' tip{Colors.ENDC}"
        )
        print()

    try:
        run_command(f"open {app_path}", "Launching Qalti.app")
        print(f"{Colors.GREEN}✓ App launched successfully{Colors.ENDC}")

        if is_first_launch:
            print()
            print(f"{Colors.YELLOW}NEXT STEPS FOR FIRST LAUNCH:{Colors.ENDC}")
            print(f"{Colors.CYAN}• Grant permissions when prompted{Colors.ENDC}")
            print(
                f"{Colors.CYAN}• If left panel is empty, close"
                f" and relaunch the app{Colors.ENDC}"
            )
            print(
                f"{Colors.CYAN}• This is a one-time macOS permission"
                f" setup process{Colors.ENDC}"
            )
        else:
            print(
                f"{Colors.YELLOW}Note: The app should now be running. "
                f"Check for permission dialogs.{Colors.ENDC}"
            )
        return True
    except subprocess.CalledProcessError:
        print(f"{Colors.RED}✗ Failed to launch app{Colors.ENDC}")
        return False


def reset_folder_permissions():
    """Reset folder access permissions for Qalti app"""
    print_step(
        "RESET",
        "Reset Folder Permissions",
        "Resetting Downloads, Documents, and Desktop access for Qalti",
    )

    app_bundle_id = "com.aiqa.Qalti"

    # Reset TCC database entries for folder access
    folders_to_reset = [
        "kTCCServiceSystemPolicyDesktopFolder",
        "kTCCServiceSystemPolicyDocumentsFolder",
        "kTCCServiceSystemPolicyDownloadsFolder",
        "kTCCServiceSystemPolicyAllFiles",
    ]

    print(f"{Colors.YELLOW}Attempting to reset folder permissions...{Colors.ENDC}")

    for folder_service in folders_to_reset:
        try:
            cmd = f"tccutil reset {folder_service} {app_bundle_id}"
            run_command(cmd, f"Resetting {folder_service}", check=False)
        except subprocess.CalledProcessError:
            print(
                f"{Colors.YELLOW}Note: Could not reset {folder_service} "
                f"(may not exist){Colors.ENDC}"
            )

    # Also try to reset all permissions for the bundle ID
    try:
        run_command(
            f"tccutil reset All {app_bundle_id}",
            "Resetting all permissions for Qalti",
            check=False,
        )
    except subprocess.CalledProcessError:
        print(f"{Colors.YELLOW}Note: Could not reset all permissions{Colors.ENDC}")

    print(f"{Colors.GREEN}✓ Permission reset commands completed{Colors.ENDC}")
    print(f"{Colors.CYAN}Manual reset option:{Colors.ENDC}")
    print(f"{Colors.CYAN}1. Open System Settings/Preferences{Colors.ENDC}")
    print(f"{Colors.CYAN}2. Go to Privacy & Security > Privacy{Colors.ENDC}")
    print(
        f"{Colors.CYAN}3. Click 'Files and Folders' or 'Full Disk Access'{Colors.ENDC}"
    )
    print(f"{Colors.CYAN}4. Remove 'Qalti' from the list if present{Colors.ENDC}")
    print(f"{Colors.CYAN}5. Restart Qalti to be prompted again{Colors.ENDC}")

    return True


def main():
    """Main build process"""

    # Parse command line arguments
    parser = argparse.ArgumentParser(
        description="Qalti Build Automation",
        epilog="Examples:\n"
        "  python scripts/build_qalti.py                    # Full build with clean\n"
        "  python scripts/build_qalti.py --no-clean        # Incremental build (faster)\n"
        "  python scripts/build_qalti.py --first-launch    # First-time setup guidance\n"
        "  python scripts/build_qalti.py --skip-launch     # Build only, don't launch\n",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--reset-permissions",
        action="store_true",
        help="Reset folder access permissions for Qalti and exit",
    )
    parser.add_argument(
        "--skip-launch",
        action="store_true",
        help="Skip launching the app after building",
    )
    parser.add_argument(
        "--first-launch",
        action="store_true",
        help="First launch mode with detailed permission setup guidance",
    )
    parser.add_argument(
        "--no-clean",
        action="store_true",
        help="Skip cleaning DerivedData (faster incremental builds)",
    )

    args = parser.parse_args()

    # If only resetting permissions, do that and exit
    if args.reset_permissions:
        reset_folder_permissions()
        return

    print(f"{Colors.HEADER}{Colors.BOLD}")
    print("🚀 Qalti Build Script (Enhanced)")
    print("Automating DEVELOPER.md instructions with modern features")
    print(f"{Colors.ENDC}")

    # Ensure we're in the right directory (should be repo root)
    if not os.path.exists("xcodeproject"):
        print(
            f"{Colors.RED}Error: xcodeproject directory not found. "
            f"Are you in the repo root?{Colors.ENDC}"
        )
        sys.exit(1)

    # Show build options
    if args.no_clean:
        print(
            f"{Colors.CYAN}🏗️  Running incremental build (DerivedData preserved){Colors.ENDC}"
        )
    else:
        print(
            f"{Colors.CYAN}🧹 Running clean build (DerivedData will be removed){Colors.ENDC}"
        )

    # Run all steps
    clean_build = not args.no_clean
    steps = [
        preflight_checks,
        generate_simulator_artifacts,
        lambda: build_macos_app(clean_derived_data=clean_build),
        verify_binaries,
    ]

    # Add launch step unless skipped
    if not args.skip_launch:
        if args.first_launch:
            steps.append(lambda: launch_app(is_first_launch=True))
        else:
            steps.append(lambda: launch_app(is_first_launch=False))

    for i, step_func in enumerate(steps, 1):
        try:
            if not step_func():
                print(f"{Colors.RED}Build failed at step {i}{Colors.ENDC}")
                sys.exit(1)
        except KeyboardInterrupt:
            print(f"\n{Colors.YELLOW}Build interrupted by user{Colors.ENDC}")
            sys.exit(1)
        except Exception as e:
            print(f"{Colors.RED}Unexpected error in step {i}: {e}{Colors.ENDC}")
            sys.exit(1)

    print(f"\n{Colors.GREEN}{Colors.BOLD}🎉 Build completed successfully!{Colors.ENDC}")
    launched_text = " and launched" if not args.skip_launch else ""
    print(f"{Colors.GREEN}The Qalti.app is now built{launched_text}.{Colors.ENDC}")
    print(f"{Colors.CYAN}Next steps (optional):{Colors.ENDC}")
    print(
        f"{Colors.CYAN}1. Set your OPENROUTER_API_KEY environment variable{Colors.ENDC}"
    )
    print(
        f"{Colors.CYAN}2. Download a test app (SyncUps) and run CLI tests{Colors.ENDC}"
    )
    if clean_build:
        print(f"{Colors.CYAN}3. For faster rebuilds, use: --no-clean flag{Colors.ENDC}")
    else:
        print(f"{Colors.CYAN}3. For clean builds, use: make build{Colors.ENDC}")


if __name__ == "__main__":
    main()

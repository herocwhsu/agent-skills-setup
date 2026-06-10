import sys, argparse, subprocess, os
from pathlib import Path
import detect
import backup

def main():
    parser = argparse.ArgumentParser(description="Host Optimization Orchestrator")
    parser.add_argument("--check",  action="store_true", help="Investigate host health (no changes)")
    parser.add_argument("--apply",  action="store_true", help="Apply performance optimizations")
    parser.add_argument("--revert", action="store_true", help="Revert optimization changes")
    args = parser.parse_args()

    # Default to --check if no flag given
    if not any([args.check, args.apply, args.revert]):
        args.check = True

    profile = detect.get_profile()
    lib_dir = Path(__file__).parent.resolve()

    if args.revert:
        print("[host-opt] Starting rollback...")
        if profile["is_macos"]:
            lib_dir = Path(__file__).parent.resolve()
            subprocess.run(["bash", str(lib_dir / "tune_macos.sh"), "--revert"], check=True)
        else:
            backup.revert()
        print("[host-opt] Done.")
        return

    if not profile["is_linux"] and not profile["is_macos"]:
        print(f"Unsupported OS: {profile['os']}")
        sys.exit(1)

    if args.check:
        if profile["is_linux"]:
            result = subprocess.run(["bash", str(lib_dir / "check_linux.sh")])
            sys.exit(result.returncode)
        else:
            print("--check is only supported on Linux.")
            sys.exit(1)

    if args.apply:
        print(f"[host-opt] Host: {profile['os'].capitalize()} | {profile['cpu_brand']} | {profile['ram_gb']}GB RAM")
        print("[host-opt] Applying performance profile...")

        if profile["is_linux"]:
            backup.backup_file("/etc/sysctl.d/99-performance.conf")
            subprocess.run(["bash", str(lib_dir / "tune_linux.sh")], check=True)
        elif profile["is_macos"]:
            subprocess.run(["bash", str(lib_dir / "tune_macos.sh")], check=True)

        print("\n[host-opt] Done. Run --check to verify.")

if __name__ == "__main__":
    main()

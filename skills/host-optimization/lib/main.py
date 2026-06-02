import sys, argparse, subprocess, os
from pathlib import Path
import detect
import backup

def main():
    parser = argparse.ArgumentParser(description="Host Optimization Orchestrator")
    parser.add_argument("--revert", action="store_true", help="Revert optimization changes")
    args = parser.parse_args()
    
    profile = detect.get_profile()
    print(f"🚀 Detected Host: {profile['os'].capitalize()} ({profile['cpu_brand']})")
    
    lib_dir = Path(__file__).parent.resolve()

    if args.revert:
        print("♻️ Starting Rollback...")
        backup.revert()
        print("DONE.")
        return

    print("🛠️ Applying Performance Profile...")
    
    if profile['is_linux']:
        # 1. Backup existing config
        backup.backup_file("/etc/sysctl.d/99-performance.conf")
        
        # 2. Run tuning script
        script = lib_dir / "tune_linux.sh"
        subprocess.run(["bash", str(script)], check=True)
        
    elif profile['is_macos']:
        # 1. Run tuning script
        script = lib_dir / "tune_macos.sh"
        subprocess.run(["bash", str(script)], check=True)
        
    else:
        print("❌ Unsupported OS for automated tuning.")
        sys.exit(1)

    print("\n✅ Host Optimization Applied Successfully!")
    print("Tip: Run 'btop' to monitor your system performance.")

if __name__ == "__main__":
    main()

import shutil, os, time, sys
from pathlib import Path

BACKUP_DIR = Path(os.path.expanduser("~/.agent-skills-setup/backups/host-optimization"))

def backup_file(path: str):
    """Creates a timestamped backup of the specified file."""
    src = Path(path)
    if not src.exists():
        return None
    
    timestamp = time.strftime("%Y%m%d-%H%M%S")
    dst_dir = BACKUP_DIR / timestamp
    dst_dir.mkdir(parents=True, exist_ok=True)
    
    dst = dst_dir / src.name
    shutil.copy2(src, dst)
    print(f"✅ Backed up {src} to {dst}")
    return dst

def revert():
    """Restores the most recent backup."""
    if not BACKUP_DIR.exists():
        print("❌ No backups found.")
        return
    
    backups = sorted([d for d in BACKUP_DIR.iterdir() if d.is_dir()])
    if not backups:
        print("❌ No backups found.")
        return
    
    latest = backups[-1]
    print(f"♻️ Restoring from {latest}...")
    
    for bf in latest.iterdir():
        if bf.name == "99-performance.conf":
            target = Path("/etc/sysctl.d/99-performance.conf")
            # Using sudo tee for restore as well
            os.system(f"cat {bf} | sudo tee {target} > /dev/null")
            os.system("sudo sysctl --system")
            print(f"✅ Restored {target}")
    
    print("Rollback complete.")

if __name__ == "__main__":
    if "--revert" in sys.argv:
        revert()

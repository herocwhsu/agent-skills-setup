import shutil, os, time, sys
from pathlib import Path


def _repo_id(start: str) -> str:
    """Repo id from the nearest .skills-repo-id at or above `start`.

    Mirrors _skills_repo_id in lib/lib.sh. Two repos installed on one machine
    must not share runtime state; absent a marker, keep the historical name.
    """
    d = Path(start).resolve()
    for cand in (d, *d.parents):
        marker = cand / ".skills-repo-id"
        if marker.is_file():
            return marker.read_text().split("\n")[0].strip() or "agent-skills-setup"
    return "agent-skills-setup"


BACKUP_DIR = Path(os.path.expanduser(f"~/.{_repo_id(__file__)}/backups/host-optimization"))


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

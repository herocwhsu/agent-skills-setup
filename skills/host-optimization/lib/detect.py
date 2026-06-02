import platform
import os
import multiprocessing
import subprocess

def get_cpu_brand():
    """Returns the CPU brand string using system-specific commands."""
    try:
        if platform.system() == "Darwin":
            return subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"]).decode().strip()
        else:
            with open("/proc/cpuinfo") as f:
                for line in f:
                    if "model name" in line:
                        return line.split(":")[1].strip()
    except Exception:
        return "Unknown"
    return "Unknown"

def get_profile():
    """Returns a dictionary containing hardware and OS details."""
    system = platform.system()
    
    # RAM detection in GB
    ram_gb = 0.0
    try:
        if system == "Darwin":
            ram_bytes = int(subprocess.check_output(["sysctl", "-n", "hw.memsize"]).decode().strip())
            ram_gb = round(ram_bytes / (1024**3), 2)
        elif system == "Linux":
            # Using os.sysconf for a standard library approach on Linux
            ram_bytes = os.sysconf('SC_PAGE_SIZE') * os.sysconf('SC_PHYS_PAGES')
            ram_gb = round(ram_bytes / (1024**3), 2)
    except Exception:
        pass

    return {
        "os": "linux" if system == "Linux" else "darwin" if system == "Darwin" else system.lower(),
        "cores": multiprocessing.cpu_count(),
        "ram_gb": ram_gb,
        "is_linux": system == "Linux",
        "is_macos": system == "Darwin",
        "cpu_brand": get_cpu_brand()
    }

if __name__ == "__main__":
    # Self-verification block
    profile = get_profile()
    print(profile)

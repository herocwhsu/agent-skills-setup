import platform, os, multiprocessing, subprocess

def get_cpu_brand():
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

def get_ram_gb():
    try:
        system = platform.system()
        if system == "Darwin":
            ram_bytes = int(subprocess.check_output(["sysctl", "-n", "hw.memsize"]).decode().strip())
        else:
            ram_bytes = os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")
        return round(ram_bytes / (1024 ** 3), 2)
    except Exception:
        return 0.0

def get_gpu_info():
    """Returns dict with vendor, driver, and whether it's a legacy Fermi-era card."""
    info = {"vendor": None, "driver": None, "is_fermi": False}
    try:
        lspci = subprocess.check_output(["lspci"], stderr=subprocess.DEVNULL).decode()
        if "NVIDIA" in lspci:
            info["vendor"] = "nvidia"
            lsmod = subprocess.check_output(["lsmod"], stderr=subprocess.DEVNULL).decode()
            if lsmod.startswith("nouveau") or "\nnouveau" in lsmod:
                info["driver"] = "nouveau"
            elif "nvidia " in lsmod:
                info["driver"] = "nvidia"
            # GF-series chip IDs appear as GF1xx in lspci description
            if "GF" in lspci or "Fermi" in lspci:
                info["is_fermi"] = True
    except Exception:
        pass
    return info

def get_cpu_max_temp():
    """Returns max CPU core temp in Celsius, or None if unavailable."""
    try:
        out = subprocess.check_output(["sensors"], stderr=subprocess.DEVNULL).decode()
        temps = []
        for line in out.splitlines():
            if "Core" in line and "°C" in line:
                part = line.split("+")[1].split("°")[0].strip()
                temps.append(float(part))
        return max(temps) if temps else None
    except Exception:
        return None

def get_profile():
    system = platform.system()
    return {
        "os":        "linux" if system == "Linux" else "darwin" if system == "Darwin" else system.lower(),
        "cores":     multiprocessing.cpu_count(),
        "ram_gb":    get_ram_gb(),
        "is_linux":  system == "Linux",
        "is_macos":  system == "Darwin",
        "cpu_brand": get_cpu_brand(),
        "gpu":       get_gpu_info() if system == "Linux" else {},
        "cpu_temp":  get_cpu_max_temp() if system == "Linux" else None,
    }

if __name__ == "__main__":
    import json
    print(json.dumps(get_profile(), indent=2))

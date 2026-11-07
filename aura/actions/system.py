import platform
import shutil
import subprocess
from typing import Any, Dict

import psutil


def _nvidia_gpu_info() -> Dict[str, Any] | None:
    try:
        out = subprocess.check_output(
            [
                "nvidia-smi",
                "--query-gpu=name,memory.total,memory.free,utilization.gpu",
                "--format=csv,noheader,nounits",
            ],
            text=True,
            timeout=5,
        ).strip()

        if not out:
            return None

        parts = [p.strip() for p in out.split(",")]
        return {
            "name": parts[0] if len(parts) > 0 else "NVIDIA GPU",
            "memory_total_mib": parts[1] if len(parts) > 1 else "",
            "memory_free_mib": parts[2] if len(parts) > 2 else "",
            "utilization_percent": parts[3] if len(parts) > 3 else "",
        }
    except Exception:
        return None


def get_system_info(args: Dict[str, Any]) -> Dict[str, Any]:
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage("/")

    data = {
        "os": platform.platform(),
        "cpu": {
            "model": platform.processor() or "Unknown",
            "cores": psutil.cpu_count(logical=False),
            "threads": psutil.cpu_count(logical=True),
            "usage_percent": psutil.cpu_percent(interval=0.3),
        },
        "ram": {
            "total_gb": round(mem.total / (1024**3), 2),
            "available_gb": round(mem.available / (1024**3), 2),
            "used_percent": mem.percent,
        },
        "disk": {
            "path": disk._path,  # type: ignore[attr-defined]
            "total_gb": round(disk.total / (1024**3), 2),
            "free_gb": round(disk.free / (1024**3), 2),
            "used_percent": disk.percent,
        },
        "gpu": _nvidia_gpu_info(),
        "python": platform.python_version(),
    }

    return {"success": True, "data": data}


def get_usage(args: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "success": True,
        "data": {
            "cpu_percent": psutil.cpu_percent(interval=0.3),
            "ram_percent": psutil.virtual_memory().percent,
            "disk_percent": psutil.disk_usage("/").percent,
        },
    }


def shutdown(args: Dict[str, Any]) -> Dict[str, Any]:
    try:
        subprocess.run(["shutdown", "/s", "/t", "0"], check=True)
        return {"success": True, "message": "Выключение инициировано."}
    except Exception as exc:
        return {"success": False, "message": f"Не удалось выключить: {exc}"}


def restart(args: Dict[str, Any]) -> Dict[str, Any]:
    try:
        subprocess.run(["shutdown", "/r", "/t", "0"], check=True)
        return {"success": True, "message": "Перезагрузка инициирована."}
    except Exception as exc:
        return {"success": False, "message": f"Не удалось перезагрузить: {exc}"}

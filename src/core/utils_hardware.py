"""
utils_hardware.py — Runtime hardware detection and configuration.

Detects available compute (CUDA GPU, Apple MPS, or CPU) and applies
the appropriate environment settings. Import and call setup_hardware()
at the top of any entry-point script (main_ke.py, main_sg.py, etc.).

Supported targets:
  - CUDA GPU      (Linux/Windows, NVIDIA — HPC or desktop with GPU)
  - Apple MPS     (macOS Apple Silicon — M1/M2/M3)
  - CPU           (macOS Intel, any machine without GPU)
"""

from __future__ import annotations

import logging
import os
import platform
from dataclasses import dataclass
from enum import Enum

logger = logging.getLogger(__name__)


# ── Device enum ───────────────────────────────────────────────────────────────

class Device(str, Enum):
    CUDA = "cuda"
    MPS  = "mps"
    CPU  = "cpu"


# ── Result dataclass ──────────────────────────────────────────────────────────

@dataclass
class HardwareInfo:
    device: Device
    device_name: str        # human-readable, e.g. "NVIDIA A100 80GB"
    num_gpus: int
    cpu_count: int
    platform: str           # e.g. "macOS-14.5-x86_64"
    cuda_version: str | None


# ── Detection ─────────────────────────────────────────────────────────────────

def detect_hardware() -> HardwareInfo:
    """
    Detect the best available compute device.

    Priority: CUDA > MPS (Apple Silicon) > CPU

    Returns:
        HardwareInfo with device type, name, and counts.
    """
    import multiprocessing
    cpu_count = multiprocessing.cpu_count()
    sys_platform = platform.platform()

    # ── Try CUDA ──────────────────────────────────────────────────────────────
    try:
        import torch
        if torch.cuda.is_available():
            num_gpus = torch.cuda.device_count()
            device_name = torch.cuda.get_device_name(0)
            cuda_version = torch.version.cuda
            return HardwareInfo(
                device=Device.CUDA,
                device_name=device_name,
                num_gpus=num_gpus,
                cpu_count=cpu_count,
                platform=sys_platform,
                cuda_version=cuda_version,
            )

        # ── Try Apple MPS (Apple Silicon only) ────────────────────────────────
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return HardwareInfo(
                device=Device.MPS,
                device_name="Apple MPS (Metal Performance Shaders)",
                num_gpus=1,
                cpu_count=cpu_count,
                platform=sys_platform,
                cuda_version=None,
            )

    except ImportError:
        logger.warning("torch not found — defaulting to CPU.")

    # ── Fallback: CPU ─────────────────────────────────────────────────────────
    return HardwareInfo(
        device=Device.CPU,
        device_name="CPU",
        num_gpus=0,
        cpu_count=cpu_count,
        platform=sys_platform,
        cuda_version=None,
    )


# ── Environment setup ─────────────────────────────────────────────────────────

def setup_hardware(
    requested_device: str = "auto",
    num_cpu_threads: int = 8,
    cuda_device_index: int = 0,
) -> HardwareInfo:
    """
    Detect hardware, validate against requested_device, and apply
    environment settings (thread counts, CUDA visibility).

    Args:
        requested_device: "auto" | "gpu" | "cpu"
        num_cpu_threads:  Number of threads for PyTorch / OpenMP / MKL.
        cuda_device_index: GPU index to use (ignored on CPU/MPS).

    Returns:
        HardwareInfo describing the resolved device.

    Raises:
        RuntimeError: If "gpu" was requested but no GPU is available.
    """
    hw = detect_hardware()

    # ── Validate against user request ─────────────────────────────────────────
    if requested_device == "gpu" and hw.device not in (Device.CUDA, Device.MPS):
        raise RuntimeError(
            "device='gpu' was requested in config.yaml but no GPU was detected.\n"
            "Set hardware.device: auto  or  hardware.device: cpu  to run on CPU."
        )

    if requested_device == "cpu":
        # Force CPU even if GPU is available
        hw = HardwareInfo(
            device=Device.CPU,
            device_name="CPU (forced)",
            num_gpus=0,
            cpu_count=hw.cpu_count,
            platform=hw.platform,
            cuda_version=None,
        )

    # ── Apply environment variables ───────────────────────────────────────────
    if hw.device == Device.CUDA:
        os.environ["CUDA_VISIBLE_DEVICES"] = str(cuda_device_index)
        # Ollama GPU settings
        os.environ.setdefault("OLLAMA_FORCE_CUDA", "1")
        os.environ.setdefault("OLLAMA_NUM_GPU", "1")
        os.environ.setdefault("OLLAMA_ACCELERATE", "1")
        os.environ.setdefault("OLLAMA_LLM_LIBRARY", "cublas")
        logger.info(
            "GPU detected: %s (CUDA %s) — CUDA_VISIBLE_DEVICES=%s",
            hw.device_name, hw.cuda_version, cuda_device_index,
        )
    elif hw.device == Device.MPS:
        # MPS does not use CUDA env vars
        os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
        logger.info("Apple MPS detected — using Metal Performance Shaders.")
    else:
        # CPU: disable any CUDA visibility, tune thread counts
        os.environ["CUDA_VISIBLE_DEVICES"] = ""
        logger.info(
            "No GPU detected — running on CPU (%d cores). "
            "Inference will be slower.",
            hw.cpu_count,
        )

    # ── CPU thread tuning (applies on all devices) ────────────────────────────
    threads = str(num_cpu_threads)
    os.environ.setdefault("OMP_NUM_THREADS",  threads)
    os.environ.setdefault("MKL_NUM_THREADS",  threads)
    os.environ.setdefault("NUMEXPR_NUM_THREADS", threads)

    try:
        import torch
        torch.set_num_threads(num_cpu_threads)
    except ImportError:
        pass

    return hw


# ── Summary printer ───────────────────────────────────────────────────────────

def log_hardware_summary(hw: HardwareInfo) -> None:
    """Log a human-readable hardware summary at INFO level."""
    logger.info("=" * 52)
    logger.info("  Hardware Summary")
    logger.info("  Platform   : %s", hw.platform)
    logger.info("  Device     : %s", hw.device.value.upper())
    logger.info("  Device name: %s", hw.device_name)
    if hw.num_gpus > 0:
        logger.info("  GPUs       : %d", hw.num_gpus)
    logger.info("  CPU cores  : %d", hw.cpu_count)
    if hw.cuda_version:
        logger.info("  CUDA       : %s", hw.cuda_version)
    logger.info("=" * 52)


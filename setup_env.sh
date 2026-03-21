#!/bin/bash
# OmniDrones Environment Setup Script
# Isaac Sim 5.1 + RTX 5090 (Blackwell SM_120) + conda
#
# Usage: source setup_env.sh
#
# Prerequisites:
#   - NVIDIA Driver 580+ (CUDA 13.0+)
#   - conda (miniforge/miniconda)
#   - RTX 5090 or compatible Blackwell GPU

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== OmniDrones Setup for Isaac Sim 5.1 + RTX 5090 ==="

# Step 1: Create conda env
if ! conda env list | grep -q "omnidrones"; then
    echo "[1/6] Creating conda environment..."
    conda create -n omnidrones python=3.11 -y
else
    echo "[1/6] Conda env 'omnidrones' already exists."
fi

eval "$(conda shell.bash hook)"
conda activate omnidrones
pip install --upgrade pip -q

# Step 2: Install Isaac Sim 5.1.0
echo "[2/6] Installing Isaac Sim 5.1.0..."
pip install "isaacsim[all,extscache]==5.1.0" --extra-index-url https://pypi.nvidia.com -q

# Step 3: Install PyTorch with CUDA 12.8 (Blackwell SM_120 support)
echo "[3/6] Installing PyTorch 2.7.0+cu128..."
pip install --force-reinstall torch==2.7.0 torchvision==0.22.0 torchaudio==2.7.0 \
    --index-url https://download.pytorch.org/whl/cu128 -q

# Fix dependency versions broken by force-reinstall
pip install numpy==1.26.0 filelock==3.13.1 fsspec==2024.6.1 markupsafe==2.1.3 \
    networkx==3.3 sympy==1.13.3 Pillow==11.3.0 typing_extensions==4.12.2 -q

# Step 4: Install IsaacLab v2.3.0
echo "[4/6] Installing IsaacLab v2.3.0..."
if [ ! -d "$SCRIPT_DIR/IsaacLab" ]; then
    git clone --branch v2.3.0 https://github.com/isaac-sim/IsaacLab.git "$SCRIPT_DIR/IsaacLab"
fi
cd "$SCRIPT_DIR/IsaacLab"
echo "Yes" | ./isaaclab.sh --install 2>&1 | tail -5

# Step 5: Clone OmniDrones (if not already present)
echo "[5/6] Setting up OmniDrones..."
if [ ! -d "$SCRIPT_DIR/OmniDrones" ]; then
    git clone https://github.com/btx0424/OmniDrones.git "$SCRIPT_DIR/OmniDrones"
fi
cd "$SCRIPT_DIR/OmniDrones"
pip install -e . -q

# Step 6: Verify
echo "[6/6] Verifying installation..."
python -c "
from isaacsim import SimulationApp
import torch
assert torch.cuda.is_available(), 'CUDA not available!'
print(f'  PyTorch: {torch.__version__}')
print(f'  CUDA: {torch.version.cuda}')
print(f'  GPU: {torch.cuda.get_device_name(0)}')
print(f'  Compute Capability: {torch.cuda.get_device_capability(0)}')
import omni_drones
print('  OmniDrones: OK')
print()
print('Setup complete! Run examples with:')
print('  conda activate omnidrones')
print('  cd $SCRIPT_DIR/OmniDrones/examples')
print('  python 00_play_drones.py headless=true')
"

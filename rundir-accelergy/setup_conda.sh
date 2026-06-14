#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Reproducibly build the `scalesim-mx` conda env so demo_22nm_walkthrough.ipynb
# and run_example_22nm.sh run end-to-end:  Accelergy + CACTI + a Jupyter kernel.
#
# Prereqs:  conda on PATH  +  a C++ toolchain (g++/make) for the CACTI build.
# Usage:    rundir-accelergy/setup_conda.sh
# ---------------------------------------------------------------------------
set -euo pipefail

ENV_NAME="${ENV_NAME:-scalesim-mx}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="${BUILD_DIR:-$HOME/.scalesim-mx-build}"        # where Accelergy sources are cloned

command -v conda >/dev/null || { echo "ERROR: conda not on PATH"; exit 1; }
source "$(conda info --base)/etc/profile.d/conda.sh"

echo ">> [1/6] python env from environment.yml (numpy<2, pandas, jupyter, ...)"
conda env create -f "$HERE/environment.yml" 2>/dev/null || conda env update -f "$HERE/environment.yml"
conda activate "$ENV_NAME"
echo "   env = $CONDA_PREFIX  ($(python --version))"

echo ">> [2/6] clone Accelergy + plug-ins (+ CACTI submodule)"
mkdir -p "$BUILD"; cd "$BUILD"
clone() { [ -d "$2/.git" ] || git clone --depth 1 "$1" "$2"; }
clone https://github.com/Accelergy-Project/accelergy.git                      accelergy
clone https://github.com/Accelergy-Project/accelergy-cacti-plug-in.git        accelergy-cacti-plug-in
clone https://github.com/Accelergy-Project/accelergy-library-plug-in.git      accelergy-library-plug-in
clone https://github.com/Accelergy-Project/accelergy-table-based-plug-ins.git accelergy-table-based-plug-ins
git -C accelergy-cacti-plug-in submodule update --init --recursive   # pulls HewlettPackard/cacti

echo ">> [3/6] build CACTI (creates the ./cacti binary the plug-in shells out to)"
make -C accelergy-cacti-plug-in/cacti -j"$(nproc)"

echo ">> [4/6] install Accelergy + plug-ins into the env"
pip install --upgrade -q pip setuptools wheel pyyaml
pip install --no-build-isolation ./accelergy ./accelergy-cacti-plug-in \
                                 ./accelergy-library-plug-in ./accelergy-table-based-plug-ins

echo ">> [5/6] register the Jupyter kernel"
python -m ipykernel install --user --name "$ENV_NAME" --display-name "Python ($ENV_NAME)"

echo ">> [6/6] point Accelergy's config at THIS env's plug-ins"
CFG="$HOME/.config/accelergy/accelergy_config.yaml"; mkdir -p "$(dirname "$CFG")"
[ -f "$CFG" ] && cp "$CFG" "$CFG.bak.$(date +%s 2>/dev/null || echo bak)" || true
cat > "$CFG" <<EOF
version: '0.4'
estimator_plug_ins:
  - $CONDA_PREFIX/share/accelergy/estimation_plug_ins
primitive_components:
  - $CONDA_PREFIX/share/accelergy/primitive_component_libs
compound_components: []
math_functions: []
python_plug_ins: []
table_plug_ins:
    roots:
      - $CONDA_PREFIX/share/accelergy/table_plug_ins
EOF

echo
echo "DONE."
echo "  check : accelergy --version  &&  jupyter kernelspec list | grep $ENV_NAME"
echo "  demo  : conda activate $ENV_NAME && jupyter lab $HERE/demo_22nm_walkthrough.ipynb"
echo "  shell : VENV=$CONDA_PREFIX $HERE/run_example_22nm.sh"

#!/usr/bin/env bash
# ===========================================================================
# One-shot environment setup for the SCALE-Sim-v3 + Accelergy + CACTI MX power
# flow.  Builds a self-contained conda env `scalesim-mx` with everything needed
# to run  rundir-accelergy/run_example_22nm.sh  and  demo_22nm_walkthrough.ipynb.
#
# For a fresh machine / new user:
#     git clone <this repo> && cd scale-sim-v3-mx
#     bash rundir-accelergy/setup_conda.sh
#     conda activate scalesim-mx
#     ./rundir-accelergy/run_example_22nm.sh
#
# Prereqs: a conda install (miniconda/anaconda/miniforge) + a C++ toolchain
#          (git, make, g++) for the CACTI build.  ~5-10 min, mostly the CACTI compile.
# Env vars: ENV_NAME (default scalesim-mx), BUILD_DIR, SMOKE=0 to skip the smoke test.
# ===========================================================================
set -euo pipefail

ENV_NAME="${ENV_NAME:-scalesim-mx}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"     # rundir-accelergy
ROOT="$(cd "$HERE/.." && pwd)"                            # repo root (has scale.py)
BUILD="${BUILD_DIR:-$HOME/.scalesim-mx-build}"           # where Accelergy sources are cloned

# ---- prereqs ---------------------------------------------------------------
for t in git make g++; do
  command -v "$t" >/dev/null 2>&1 || { echo "ERROR: '$t' not found — needed for the CACTI build"; exit 1; }
done

# ---- locate conda (it's often installed but not on PATH) -------------------
if ! command -v conda >/dev/null 2>&1; then
  for c in "$HOME/miniconda3" "$HOME/anaconda3" "$HOME/miniforge3" "$HOME/mambaforge" /opt/conda; do
    [ -f "$c/etc/profile.d/conda.sh" ] && { source "$c/etc/profile.d/conda.sh"; break; }
  done
fi
command -v conda >/dev/null 2>&1 || { echo "ERROR: conda not found. Install miniconda first."; exit 1; }
source "$(conda info --base)/etc/profile.d/conda.sh"

echo ">> [1/7] create/update conda env '$ENV_NAME' (python<3.13, numpy<2, jupyter)"
conda env create -n "$ENV_NAME" -f "$HERE/environment.yml" 2>/dev/null \
  || conda env update -n "$ENV_NAME" -f "$HERE/environment.yml"
conda activate "$ENV_NAME"
echo "   env = $CONDA_PREFIX  ($(python --version))"

echo ">> [2/7] clone Accelergy + plug-ins (+ HewlettPackard/cacti submodule)"
mkdir -p "$BUILD"; cd "$BUILD"
# Pinned to the exact commits proven to work with this flow — avoids upstream-main drift.
clone_at() {  # url dir commit
  [ -d "$2/.git" ] || git clone -q "$1" "$2"
  git -C "$2" checkout -q "$3" 2>/dev/null || { git -C "$2" fetch -q origin "$3" && git -C "$2" checkout -q "$3"; }
}
clone_at https://github.com/Accelergy-Project/accelergy.git                      accelergy                      6911d15686ee7efdceba7d95605102df4472ae3a
clone_at https://github.com/Accelergy-Project/accelergy-cacti-plug-in.git        accelergy-cacti-plug-in        7649b2c02a389f3c3d585d7ff4ececacfb01e6ea
clone_at https://github.com/Accelergy-Project/accelergy-library-plug-in.git      accelergy-library-plug-in      ba4e9dac1b2e7a3076fb8b7816a5228211623055
clone_at https://github.com/Accelergy-Project/accelergy-table-based-plug-ins.git accelergy-table-based-plug-ins  bad19e941043045e130ea999852331f203d8c3fe
git -C accelergy-cacti-plug-in submodule update --init --recursive   # pulls the pinned HewlettPackard/cacti (1ffd8df)

echo ">> [3/7] build CACTI (the ./cacti binary the plug-in shells out to)"
make -C accelergy-cacti-plug-in/cacti -j"$(nproc)"

echo ">> [4/7] pip install Accelergy + plug-ins into the env"
pip install --upgrade -q pip setuptools wheel pyyaml
pip install -q --no-build-isolation ./accelergy ./accelergy-cacti-plug-in \
                                    ./accelergy-library-plug-in ./accelergy-table-based-plug-ins

# ensure the built CACTI binary is where the wrapper looks (copy if setup.py didn't)
PLUG="$CONDA_PREFIX/share/accelergy/estimation_plug_ins/accelergy-cacti-plug-in"
[ -x "$PLUG/cacti" ] || cp "$BUILD/accelergy-cacti-plug-in/cacti/cacti" "$PLUG/cacti" 2>/dev/null || true

echo ">> [5/7] register the Jupyter kernel"
python -m ipykernel install --user --name "$ENV_NAME" --display-name "Python ($ENV_NAME)"

echo ">> [6/7] point Accelergy's config at THIS env's plug-ins"
CFG="$HOME/.config/accelergy/accelergy_config.yaml"; mkdir -p "$(dirname "$CFG")"
[ -f "$CFG" ] && cp "$CFG" "$CFG.bak.$$" || true
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

echo ">> [7/7] smoke test"
ok=1
python - <<'PY' || ok=0
import numpy, pandas, yaml
assert int(numpy.__version__.split('.')[0]) < 2, f"numpy {numpy.__version__} must be <2"
print(f"   python deps  OK  (numpy {numpy.__version__}, pandas {pandas.__version__})")
PY
accelergy --help >/dev/null 2>&1 && echo "   accelergy    OK" || { echo "   accelergy    FAIL"; ok=0; }
[ -x "$PLUG/cacti" ] && echo "   CACTI binary OK" || { echo "   CACTI binary MISSING"; ok=0; }
PYTHONPATH="$ROOT" python -c "import scalesim.scale_sim" 2>/dev/null && echo "   scalesim     OK" || { echo "   scalesim     FAIL"; ok=0; }
if [ "${SMOKE:-1}" = "1" ] && [ "$ok" = "1" ]; then
  echo "   running a tiny end-to-end (32x64x64 GEMM)..."
  printf "Layer,M,N,K,\nSmoke,32,64,64,\n" > /tmp/_scalesim_smoke.csv
  if VENV="$CONDA_PREFIX" bash "$HERE/run_example_22nm.sh" "$ROOT/configs/scale_accel.cfg" /tmp/_scalesim_smoke.csv gemm >/tmp/_scalesim_smoke.log 2>&1; then
    echo "   end-to-end   OK  ($(grep -aoE '[0-9.]+ W' /tmp/_scalesim_smoke.log | tail -1))"
  else
    echo "   end-to-end   FAIL — see /tmp/_scalesim_smoke.log"; ok=0
  fi
  rm -f /tmp/_scalesim_smoke.csv
fi

echo
[ "$ok" = "1" ] && echo "SETUP OK." || { echo "SETUP INCOMPLETE — see messages above."; exit 1; }
echo "  run :  conda activate $ENV_NAME && ./rundir-accelergy/run_example_22nm.sh"
echo "  demo:  conda activate $ENV_NAME && jupyter lab rundir-accelergy/demo_22nm_walkthrough.ipynb   (kernel: Python ($ENV_NAME))"

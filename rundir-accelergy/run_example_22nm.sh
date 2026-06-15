#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Native Accelergy + CACTI energy for the 32x32 transformer example, at 22nm,
# with the systolic-array (PE) energy taken from energy/pe_netlist.json — the
# slot for your synthesized MX netlist. CACTI supplies all memory (SRAM/DRAM)
# energy; SCALE-Sim (THIS repo's scale.py) supplies the activity counts,
# including the measured per-PE register-file accesses (DETAILED_ACCESS cols 19-24).
#
# Pipeline (self-contained — this repo IS scale-sim-v3):
#   preprocess.py  (scale.cfg -> accelergy_input/architecture.yaml @ --technology)
#   scale.py       (activity: COMPUTE / DETAILED_ACCESS / REPEAT_CYCLE reports)
#   create_action_count.sh  (reports -> action_count.yaml; measured spad counts)
#   run_accelergy.sh        (Accelergy + CACTI -> ERT.yaml, energy_estimation.yaml)
#   accelergy_eval.py       (inject PE netlist ERT -> ACCELERGY_SUMMARY.md + watts)
#
# Usage (from anywhere):
#   rundir-accelergy/run_example_22nm.sh                       # 32x32 transformer @ 22nm
#   TECH=45nm     rundir-accelergy/run_example_22nm.sh         # other CACTI node
#   CLOCK_HZ=2e8  rundir-accelergy/run_example_22nm.sh         # change the watt clock
#   rundir-accelergy/run_example_22nm.sh <cfg> <topo> <gemm|conv>
# ---------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"     # .../rundir-accelergy
ROOT="$(cd "$HERE/.." && pwd)"                            # scale-sim-v3-mx root (has scale.py)

# env that has accelergy + CACTI + numpy<2 + pandas/yaml. Defaults to the active conda env
# (so `conda activate scalesim-mx` then run just works on any machine); override with VENV=...
VENV="${VENV:-${CONDA_PREFIX:-/home/xinting/miniconda3/envs/scalesim-mx}}"
export PATH="$VENV/bin:$PATH"                             # python3, accelergy resolve here

TECH="${TECH:-22nm}"
CLK="${CLOCK_HZ:-1e9}"
CFG="$(realpath "${1:-$ROOT/configs/scale_accel.cfg}")"
TOPO="$(realpath "${2:-$ROOT/topologies/GEMM_mnk/transformer_partial.csv}")"
KIND="${3:-gemm}"

RUN_NAME=$(grep -E '^run_name' "$CFG" | head -1 | sed 's/.*=[[:space:]]*//' | tr -d ' ')
SCSIM="/tmp/${RUN_NAME}_scsim"
OUT="/tmp/${RUN_NAME}_out"
rm -rf "$SCSIM" "$OUT"; mkdir -p "$SCSIM" "$OUT"
SCSIM="$(realpath "$SCSIM")"; OUT="$(realpath "$OUT")"

echo "config=$CFG"
echo "topo=$TOPO  kind=$KIND  tech=$TECH  clock=$CLK"
echo "run_name=$RUN_NAME"
echo "out=$OUT"
echo

cd "$HERE"
rm -f accelergy_input/*.yaml

echo ">> [1/5] preprocess -> architecture.yaml (+regenerate action/accelergy scripts) @ $TECH"
python3 preprocess.py -c "$CFG" -t "$TOPO" -p "$SCSIM" -o "$OUT" --technology "$TECH"

echo ">> [2/5] SCALE-Sim activity (this repo's scale.py; emits per-PE spad counts): $RUN_NAME"
( cd "$ROOT" && python3 scale.py -c "$CFG" -t "$TOPO" -p "$SCSIM" -i "$KIND" -s N )

echo ">> [3/5] reports -> action_count.yaml"
./create_action_count.sh

echo ">> [4/5] Accelergy + CACTI -> ERT.yaml + energy_estimation.yaml"
./run_accelergy.sh

echo ">> [5/5] inject PE netlist ERT (MX slot) + final multiply"
CYC=$(awk -F, 'NR>1{s+=$3} END{printf "%d", s}' "$OUT/scale_sim_output_${RUN_NAME}/COMPUTE_REPORT.csv")
python3 accelergy_eval.py \
    --ert           "$OUT/accelergy_output_${RUN_NAME}/ERT.yaml" \
    --action-count  "$OUT/scale_sim_output_${RUN_NAME}/action_count.yaml" \
    --pe-energy     "$ROOT/energy/pe_netlist.json" \
    --cycles "$CYC" --clock-hz "$CLK" --model "$RUN_NAME" \
    --out "$OUT/energy_${RUN_NAME}"

echo
echo "DONE. Outputs:"
echo "  CACTI energy_estimation.yaml : $OUT/accelergy_output_${RUN_NAME}/energy_estimation.yaml"
echo "  Final summary (with MX PE)   : $OUT/energy_${RUN_NAME}/ACCELERGY_SUMMARY.md"

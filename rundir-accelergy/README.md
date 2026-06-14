# rundir-accelergy

Native **SCALE-Sim → Accelergy + CACTI** energy flow, adapted for the MX (microscaling)
systolic-array study. Division of labor:

- **SCALE-Sim** (this repo's `scale.py`) → activity: MAC-cycles, SRAM/DRAM **and per-PE register-file** access counts, runtime.
- **CACTI** (via Accelergy) → real memory energy (SRAM @ the chosen node, off-chip DRAM).
- **Your MX netlist** (`../energy/pe_netlist.json`) → the systolic-array (PE/MAC) energy,
  injected over Accelergy's dummy MAC.

## Run

```bash
./run_example_22nm.sh                      # 32x32 MAC array (16x16 PEs x 4 MAC) @ 22nm
TECH=45nm     ./run_example_22nm.sh        # different CACTI node
CLOCK_HZ=2e8  ./run_example_22nm.sh        # clock used only for the watt figure
./run_example_22nm.sh <cfg> <topo> <gemm|conv>   # override config / workload
```

Results land in `/tmp/<run_name>_out/` (run_name comes from the config):

- `accelergy_output_<run>/energy_estimation.yaml` — Accelergy/CACTI energy
- `energy_<run>/ACCELERGY_SUMMARY.md` — final breakdown + watts (with the MX PE injected)

Needs an env with `accelergy` + CACTI + `numpy<2` on it
(default `VENV=~/miniconda3/envs/scalesim-mx`; override with `VENV=...`). See **Conda environment** below.

## Pipeline (what `run_example_22nm.sh` chains)

| # | stage | role |
|---|---|---|
| 1 | `preprocess.py` | `scale.cfg` → `accelergy_input/architecture.yaml` (@ `--technology`); also regenerates `create_action_count.sh` + `run_accelergy.sh` |
| 2 | `scale.py` (this repo) | activity sim → COMPUTE / DETAILED_ACCESS / REPEAT_CYCLE (incl. **measured per-PE register-file** counts, cols 19-24) |
| 3 | `create_action_count.py` | reports → `action_count.yaml` |
| 4 | `accelergy` (+ CACTI) | architecture + action counts → `ERT.yaml`, `energy_estimation.yaml` |
| 5 | `accelergy_eval.py` | inject the MX PE-netlist ERT → `ACCELERGY_SUMMARY.md` + watts |

`run_example_22nm.sh` is the **one-shot bash equivalent of `demo_22nm_walkthrough.ipynb`** — the
same five stages and the same commands; the notebook just annotates them. `clean.sh` removes
generated artifacts.

## Files

**Source (tracked):**

```
preprocess.py  create_action_count.py  accelergy_eval.py   pipeline stages (1, 3, 5)
run_example_22nm.sh                                         one-shot driver (= the .ipynb, as a script)
demo_22nm_walkthrough.ipynb                                annotated walkthrough of the same flow
clean.sh                                                   remove generated artifacts
environment.yml  setup_conda.sh                            build the scalesim-mx conda env
accelergy_input/components/*.yaml                          Accelergy compound-component library
README.md  .gitignore
```

**Generated each run (gitignored — see `.gitignore`):**

```
accelergy_input/architecture.yaml   accelergy_input/action_count.yaml
create_action_count.sh   run_accelergy.sh     (rewritten by preprocess.py)
accelergy_output/                              (moved to the run's /tmp output dir)
```

## Notes

- Config + knobs: `../configs/scale_accel.cfg`. Array = **32x32 MAC cells = 16x16 PEs × 4 MACs**
  (SCALE-Sim models 1 MAC/cell, so a 4-MAC PE is a 2×2 tile of cells). `SRAM_row_size` /
  `DRAM_row_size` in that config are read by this flow (ignored by scalesim).
- **Activity engine is this repo's `scale.py`** (no external checkout). It emits the per-PE
  register-file access counts (`DETAILED_ACCESS` cols 19-24, via
  `scalesim/compute/*.get_pe_action_count`) and `REPEAT_CYCLE.csv`, so `pe_regfile` and the SRAM
  random/repeat split are **measured, not fabricated**. `create_action_count.py` aborts if those
  columns are ever missing rather than reconstructing them.
- `pe_regfile` is the **measured** per-PE scratchpad accesses × `spad` energy in
  `../energy/pe_netlist.json` (currently 0.02 pJ/access — replace with your MX netlist's value;
  it is the lever, not the count).
- DRAM energy is node-independent (CactiDRAM models LPDDR4 by type+width); only on-chip SRAM
  scales with `TECH`.
- **On-chip SRAM = a bare CACTI SRAM** (`components/cacti_SRAM.yaml`), not `smartbuffer_SRAM`.
  The smartbuffer compound adds buffet scoreboard / FIFOs / address counters that have no real ERT
  and fall to Accelergy's flat-1.0 pJ **dummy** estimator (~half the old SRAM line was fabricated).
  A plain SRAM is 100% CACTI physics and matches SCALE-Sim's simple scratchpad model; the (real but
  unmodelled) buffer-control overhead is **omitted, not faked**.
- **No fabricated term remains.** Every reported pJ is either CACTI physics (DRAM, SRAM) or your MX
  netlist × a simulator-measured access count (MAC, RF). Nothing falls to the dummy estimator. The
  only modelling assumptions left are the tool's own (CACTI's memory physics) and yours (the netlist
  pJ/op in `../energy/pe_netlist.json`).

## Conda environment

`demo_22nm_walkthrough.ipynb` and `run_example_22nm.sh` need one env with **Accelergy + CACTI +
`numpy<2` + Jupyter**. Build it once:

```bash
conda env create -f rundir-accelergy/environment.yml   # python side
rundir-accelergy/setup_conda.sh                         # accelergy + CACTI build + kernel + config
```

`setup_conda.sh` clones Accelergy and its plug-ins, builds CACTI (HewlettPackard/cacti), installs
everything into the `scalesim-mx` env, registers a Jupyter kernel of the same name, and points
`~/.config/accelergy/accelergy_config.yaml` at this env's plug-ins. Then:

```bash
# notebook  — pick the "Python (scalesim-mx)" kernel, Run All
conda activate scalesim-mx && jupyter lab rundir-accelergy/demo_22nm_walkthrough.ipynb
# shell     — point the driver at the conda env
VENV=~/miniconda3/envs/scalesim-mx rundir-accelergy/run_example_22nm.sh
```

Notes:
- **Self-contained:** stage 2 is this repo's own `scale.py` (already patched so `-s N` skips the
  multi-GB per-cycle trace dump — `save_disk_space=save_space`). No external checkout, no `SCALESIM_LEGACY`.
- **`numpy` must stay `<2`** (pinned to 1.26.4) — scalesim's memory model breaks on numpy 2.x.
- The accelergy config is **global** (`~/.config/accelergy/`), so it points at one install at a time;
  `setup_conda.sh` backs up the previous one. CACTI's `accuracy: 80%` in the logs is the plug-in's
  self-declared confidence used to win Accelergy's estimator auction — **not** a 20% error on the result.

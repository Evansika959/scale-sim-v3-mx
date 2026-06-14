#!/usr/bin/env python3
"""
accelergy_eval.py -- finish the native v3 Accelergy energy estimation with an injected
PE (array) ERT.

The native flow (run_example_22nm.sh, stages 1-4) gives REAL CACTI memory energies but
leaves the array (mac, spad) at a dummy 1.0 pJ, because CACTI is memory-only. This injects
the array's per-action energies (your MX netlist, energy/pe_netlist.json) into the ERT and
performs Accelergy's final multiply (action_count x ERT), categorized into
array / SRAM / DRAM and turned into watts.

Inputs (all produced by stages 1-4 of run_example_22nm.sh):
  --ert           accelergy_output_<run>/ERT.yaml           (CACTI memory + dummy compute)
  --action-count  scale_sim_output_<run>/action_count.yaml
  --pe-energy     energy/pe_netlist.json                     (mac/spad pJ; the netlist slot)
  --cycles N --clock-hz HZ                                   (runtime -> power)
"""
import argparse, yaml, json, collections, os

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ert", required=True)
    ap.add_argument("--action-count", required=True)
    ap.add_argument("--pe-energy", default=os.path.join(HERE, "energy", "pe_netlist.json"))
    ap.add_argument("--cycles", type=float, required=True)
    ap.add_argument("--clock-hz", type=float, default=1e9)
    ap.add_argument("--model", default="run")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    pe = json.load(open(args.pe_energy))
    L = {}                                   # ERT lookup by component base-name
    for t in yaml.safe_load(open(args.ert))["ERT"]["tables"]:
        base = t["name"].split(".")[-1].split("[")[0]
        L[base] = {a["name"]: a["energy"] for a in t["actions"]}
    for base in L:                           # inject netlist PE energies; zero static
        if base == "mac":
            L[base].update(pe["mac"])
        elif base.endswith("spad"):
            L[base].update(pe["spad"])
        for k in ("idle", "leak"):
            if k in L[base]:
                L[base][k] = 0.0             # counts can be negative artifacts -> ignore

    A = yaml.safe_load(open(args.action_count))["action_counts"]["local"]
    cat = collections.defaultdict(float)
    for e in A:
        base = e["name"].split(".")[-1].split("[")[0]
        ed = L.get(base, {})
        ce = sum(a["counts"] * ed.get(a["name"], 0.0) for a in e["action_counts"])
        k = ("dram" if "dram" in base else "sram" if "glb" in base else
             "array_mac" if base == "mac" else "pe_regfile" if "spad" in base else "other")
        cat[k] += ce

    tot = sum(cat.values())
    rt = args.cycles / args.clock_hz
    res = {"model": args.model, "cycles": args.cycles, "clock_hz": args.clock_hz,
           "runtime_s": rt, "total_energy_J": tot * 1e-12, "avg_power_W": tot * 1e-12 / rt,
           "breakdown_pJ": dict(cat), "source": "native v3 Accelergy/CACTI + injected PE ERT"}
    os.makedirs(args.out, exist_ok=True)
    json.dump(res, open(os.path.join(args.out, "ACCELERGY_ENERGY.json"), "w"), indent=2)

    lines = [f"# Accelergy (v3 native + CACTI) energy — {args.model}\n",
             f"Memory = real CACTI; array (mac/spad) = energy/pe_netlist.json (your MX netlist slot).\n",
             "| component | energy | % |", "|---|---:|---:|"]
    for k in ("array_mac", "pe_regfile", "sram", "dram"):
        v = cat.get(k, 0.0)
        lines.append(f"| {k} | {v*1e-9:.4f} mJ | {100*v/tot:.1f}% |")
    lines += [f"| **total** | **{tot*1e-9:.4f} mJ** | 100% |", "",
              f"Runtime {rt*1e3:.3f} ms @ {args.clock_hz/1e9:g} GHz -> **{tot*1e-12/rt:.2f} W**"]
    open(os.path.join(args.out, "ACCELERGY_SUMMARY.md"), "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\nwrote {args.out}/ACCELERGY_ENERGY.json + ACCELERGY_SUMMARY.md")


if __name__ == "__main__":
    main()

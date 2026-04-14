"""
build_callgraph.py — Generate a Graphviz DOT file mapping the PAGe pipeline
function call graph, grouped by pipeline stage.

Output: docs/callgraph.dot  (paste into https://dreampuf.github.io/GraphvizOnline)
        docs/callgraph.html (standalone HTML via graphviz-py if available)
"""
import re, os, glob, textwrap
from collections import defaultdict

os.chdir(r"C:\Users\lennon.li\Documents\claude\PAGe")

# ─────────────────────────────────────────────────────────────────
# 1.  Stage / group assignments  (manually curated — source of truth)
# ─────────────────────────────────────────────────────────────────
STAGES = {
    # ── M0 ──────────────────────────────────────────────────────
    "M0: Ignition": [
        "fitIgnition", "scoreIgnition", "flag_ignition_rules",
        "run_ignition_detection", "run_m0_detection",
        "m0_retro_run", "m0_retro_score",
        "apply_ignition_threshold",
    ],
    # ── M1 ──────────────────────────────────────────────────────
    "M1: Reference": [
        "build_reference_curve", "fit_reference_gam", "get_ref_curve",
        "get_ref_params", "get_ref_fit", "get_ref_n_weeks",
        "load_reference", "reference_from_hist",
    ],
    "M1: Alignment": [
        "align_season", "align_season_multi",
        "run_alignment_prospective", "run_alignment_loso",
        "m1_fit_season", "m1_align_one",
        "m1_walkforward_predictions", "m1_walkforward_multi",
        "inject_m1_into_snapshots",
        "multi_template_align", "ensemble_align",
        "weibull_template_weights",
        "compute_peak_status", "get_peak_status",
        "m1_peak_week_dist", "summarise_peak_dist",
    ],
    "M1: LOSO Tuning": [
        "loso_m1_cv", "nested_loso_m1",
        "run_m1_loso_fold", "score_m1_loso",
        "m1_loso_grid_search",
    ],
    # ── M2 Spec / Features ─────────────────────────────────────
    "M2: Spec & Features": [
        "stage2_make_spec", "expand_grid_specs",
        "stage2_build_joint_formula", "stage2_exclude_newseason",
        "prep_stage2_joint", "add_prospective_derivs_link",
        "stage2_ramp_weight", "logit_stable", "make_soft_cap_fn",
        "format_current_for_stage2",
    ],
    # ── M2 Training ─────────────────────────────────────────────
    "M2: Training": [
        "train_stage2_joint", "train_stage2_joint_prepped",
        "refit_stage2_weekly", "stage2_spec_from_tuning",
        "score_stage2_metrics",
        "nested_loso_m2_eval_fold", "nested_loso_m2_eval_weekly_refit",
        "nested_loso_refit_best",
        "loso_m1_m2_joint",
    ],
    # ── M2 Grid Tuning ──────────────────────────────────────────
    "M2: Grid Tuning": [
        "nested_loso_grid_search", "nested_loso_parallel",
        "m2_nested_loso_score", "select_best_spec",
        "plot_stage2_joint_fit_by_season",
    ],
    # ── M2 Predict ──────────────────────────────────────────────
    "M2: Predict": [
        "m2_predict_one",
    ],
    # ── Deployment Pipeline ─────────────────────────────────────
    "Deployment": [
        "run_prospective_pipeline", "run_m2_forecast",
        "run_m1_forecast", "run_m0_forecast",
        "run_weekly_pipeline",
    ],
    # ── Utilities ───────────────────────────────────────────────
    "Utilities": [
        "safe_logit", "clamp", "nll_binom", "brier_score",
        "weibull_weights", "mmwr_to_date", "season_of_date",
    ],
}

# Colour palette per stage
COLOURS = {
    "M0: Ignition":       ("#fff3cd", "#856404"),
    "M1: Reference":      ("#d4edda", "#155724"),
    "M1: Alignment":      ("#c3e6cb", "#155724"),
    "M1: LOSO Tuning":    ("#b8dacc", "#0c4a30"),
    "M2: Spec & Features":("#cce5ff", "#004085"),
    "M2: Training":       ("#b8d4f0", "#003060"),
    "M2: Grid Tuning":    ("#9ec5e8", "#002050"),
    "M2: Predict":        ("#e2ccff", "#4a0080"),
    "Deployment":         ("#f8d7da", "#721c24"),
    "Utilities":          ("#e2e3e5", "#383d41"),
}

# ─────────────────────────────────────────────────────────────────
# 2.  Parse R source files → {fn: set(called_fns)}
# ─────────────────────────────────────────────────────────────────
SKIP_FILES = {"retired.R"}

all_fn_names = set(fn for fns in STAGES.values() for fn in fns)
fn_source    = {}   # fn_name -> source file (base name)

# Gather all defined functions first by scanning source
def_pattern = re.compile(r'^([a-zA-Z_][a-zA-Z0-9._]+)\s*<-\s*function')
call_bodies  = {}   # fn_name -> raw body text

r_files = [f for f in glob.glob("R/*.R")
           if os.path.basename(f) not in SKIP_FILES]

# Map fn -> source file
defined_fns = {}   # fn_name -> file
for path in r_files:
    fname = os.path.basename(path)
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()
    for i, line in enumerate(lines):
        m = def_pattern.match(line)
        if m:
            fn = m.group(1)
            defined_fns[fn] = fname

# Build body text per function (lines between definition and next top-level fn)
for path in r_files:
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()
    # find all function start indices
    starts = []
    for i, line in enumerate(lines):
        m = def_pattern.match(line)
        if m:
            starts.append((i, m.group(1)))
    for idx, (start_i, fn_name) in enumerate(starts):
        end_i = starts[idx + 1][0] if idx + 1 < len(starts) else len(lines)
        call_bodies[fn_name] = "".join(lines[start_i:end_i])

# ─────────────────────────────────────────────────────────────────
# 3.  Build call edges (only between curated functions)
# ─────────────────────────────────────────────────────────────────
call_pattern = re.compile(r'\b([a-zA-Z_][a-zA-Z0-9._]+)\s*\(')

edges = set()   # (caller, callee)
for caller, body in call_bodies.items():
    if caller not in all_fn_names:
        continue
    for m in call_pattern.finditer(body):
        callee = m.group(1)
        if callee != caller and callee in all_fn_names:
            edges.add((caller, callee))

print(f"Functions in graph:  {len(all_fn_names)}")
print(f"Functions with body: {len([f for f in all_fn_names if f in call_bodies])}")
print(f"Edges found:         {len(edges)}")

# ─────────────────────────────────────────────────────────────────
# 4.  Emit DOT
# ─────────────────────────────────────────────────────────────────
# safe node id
def nid(name):
    return re.sub(r'[^a-zA-Z0-9_]', '_', name)

lines_dot = []
lines_dot.append('digraph PAGe_pipeline {')
lines_dot.append('  graph [rankdir=LR, fontname="Helvetica", fontsize=11, splines=ortho, nodesep=0.4, ranksep=1.2];')
lines_dot.append('  node  [fontname="Helvetica", fontsize=10, style=filled, shape=box, margin="0.15,0.06"];')
lines_dot.append('  edge  [fontname="Helvetica", fontsize=9, arrowsize=0.7];')
lines_dot.append('')

# Subgraphs per stage
for stage, fns in STAGES.items():
    bg, fg = COLOURS[stage]
    safe_stage = re.sub(r'[^a-zA-Z0-9]', '_', stage)
    lines_dot.append(f'  subgraph cluster_{safe_stage} {{')
    lines_dot.append(f'    label="{stage}";')
    lines_dot.append(f'    style=filled; color="{fg}"; fillcolor="{bg}";')
    lines_dot.append(f'    fontcolor="{fg}"; fontsize=12; fontname="Helvetica-Bold";')
    for fn in fns:
        src = defined_fns.get(fn, "")
        tooltip = f"{fn}() — {src}" if src else fn
        has_body = fn in call_bodies
        shape = "box" if has_body else "ellipse"
        lines_dot.append(f'    {nid(fn)} [label="{fn}", tooltip="{tooltip}", shape={shape}];')
    lines_dot.append('  }')
    lines_dot.append('')

# Edges
lines_dot.append('  // Call edges')
for caller, callee in sorted(edges):
    lines_dot.append(f'  {nid(caller)} -> {nid(callee)};')

lines_dot.append('}')

dot_text = "\n".join(lines_dot)
os.makedirs("docs", exist_ok=True)
with open("docs/callgraph.dot", "w") as fh:
    fh.write(dot_text)
print("\nWrote docs/callgraph.dot")
print("Paste at: https://dreampuf.github.io/GraphvizOnline")

# ─────────────────────────────────────────────────────────────────
# 5.  Also print a text summary of key call chains
# ─────────────────────────────────────────────────────────────────
print("\n── Key call chains ──────────────────────────────────────")
chains = {
    "Deployment → M2 forecast": ["run_prospective_pipeline","run_m2_forecast","m2_predict_one","make_soft_cap_fn"],
    "M2 weekly refit": ["run_m2_forecast","refit_stage2_weekly","train_stage2_joint","m2_predict_one"],
    "M2 LOSO eval (refit)": ["nested_loso_grid_search","nested_loso_m2_eval_weekly_refit","m2_predict_one"],
    "M2 LOSO eval (frozen)": ["nested_loso_grid_search","nested_loso_m2_eval_fold","m2_predict_one"],
    "Training → production model": ["nested_loso_refit_best","train_stage2_joint_prepped","stage2_make_spec"],
    "Feature prep": ["prep_stage2_joint","add_prospective_derivs_link","stage2_ramp_weight"],
    "Spec construction": ["stage2_make_spec","stage2_build_joint_formula","stage2_exclude_newseason"],
    "M1 alignment": ["run_alignment_prospective","align_season_multi","multi_template_align","ensemble_align"],
    "M1 walk-forward": ["m1_walkforward_predictions","align_season","inject_m1_into_snapshots"],
}
for label, chain in chains.items():
    print(f"\n  {label}:")
    print("    " + " → ".join(chain))

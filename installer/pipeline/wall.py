"""P4: animation wall (clip-list total) for MAIN and every combination of the animation-touching hot components;
WALL_BASE + StateWall (single-component deltas) + the EXACT total of every combination of those components (rc8 switch
prep 2026-10-03: DMN + NRM is built on a Wylder-off sibling NRM layer, so its total is not base + the two deltas; the
installer takes WallComboTotal when the catalog has it, else the additive model)."""
from __future__ import annotations

import itertools
import json
from pathlib import Path

from . import cfg, util
from .util import log, read_json, require, run, sha256_file, write_json


def resolve(tree: dict, conv_mod: Path, vanilla_chr: Path) -> dict:
    """binder name -> effective file: the install tree, then pristine Convergence's mod\\chr, then the vanilla game"""
    out = {}
    for name in cfg.WALL_FILES:
        p = tree.get("mod\\chr\\" + name)
        if p is None and (conv_mod / "chr" / name).exists():
            p = conv_mod / "chr" / name
        if p is None and (vanilla_chr / name).exists():
            p = vanilla_chr / name
        out[name] = str(p) if p else ""
    return out


def count(rc_name: str, specs: dict) -> dict:
    """specs {label: {name: path}} -> {label: result}; cached by the sha256 of every file AND of wallcount.py (a
    changed counting tool counts again)"""
    cache_p = cfg.WORK / "wall_cache.json"
    cache = read_json(cache_p) if cache_p.exists() else {}
    tool = sha256_file(cfg.TOOLS / "wallcount.py")
    keys = {lab: util.fingerprint({"files": {n: (sha256_file(p) if p else None) for n, p in sp.items()}, "tool": tool})
            for lab, sp in specs.items()}
    todo = {lab: sp for lab, sp in specs.items() if keys[lab] not in cache}
    if todo:
        spec_p = util.guard_write(cfg.PRODUCTS / rc_name / "_wall_spec.json")
        out_p = cfg.PRODUCTS / rc_name / "_wall_out.json"
        write_json(spec_p, todo)
        r = run(cfg.PY311 + [cfg.TOOLS / "wallcount.py", spec_p, out_p], cwd=cfg.V65 / "opus" / "work",
                log_to=cfg.LOGS / ("wallcount_%s.log" % rc_name), timeout=3600)
        require(r.returncode == 0, "wallcount.py failed: %s" % r.stderr[-2000:])
        res = json.loads(out_p.read_text(encoding="utf-8"))
        for lab in todo:
            cache[keys[lab]] = res[lab]
        write_json(cache_p, cache)
        spec_p.unlink()
        out_p.unlink()
    return {lab: cache[keys[lab]] for lab in specs}


def measure(src: dict, rc_name: str, comps: list, combo_tree, anim_comps: list) -> dict:
    """combo_tree(states: {comp id: state index}) -> full tree {rel: file}. anim_comps = hot comps that change any binder.
    -> {"base", "state_wall": {comp id: [delta per state]}, "measured": {label: total}}"""
    inp = src["inputs"]
    conv_mod = Path(inp["convergence_pristine"]) / "mod"
    van = Path(inp["vanilla_chr_for_wall"])
    combos = []
    for states in itertools.product(*[range(c["n_states"]) for c in anim_comps]):
        combos.append({c["id"]: s for c, s in zip(anim_comps, states)})
    if not combos:
        combos = [{}]

    def label(st):
        on = ["%s=%d" % (k, v) for k, v in sorted(st.items()) if v]
        return "main" + ("+" + "+".join(on) if on else "")

    specs = {label(st): resolve(combo_tree(st), conv_mod, van) for st in combos}
    res = count(rc_name, specs)
    base = res["main"]["total"]
    state_wall = {}
    for c in comps:
        state_wall[c["id"]] = [0] * c["n_states"]
    for c in anim_comps:
        for s in range(1, c["n_states"]):
            state_wall[c["id"]][s] = res[label({c["id"]: s})]["total"] - base
    not_additive = []
    for st in combos:
        model = base + sum(state_wall[k][v] for k, v in st.items())
        if model != res[label(st)]["total"]:
            not_additive.append("%s measured %d, additive %d" % (label(st), res[label(st)]["total"], model))
    # the exact table: one total per combination, the first animation component's state counting fastest (the
    # installer's CurrentWallTotal indexes it the same way)
    combo_ids = [c["id"] for c in anim_comps]
    combo_totals = []
    for states in itertools.product(*[range(c["n_states"]) for c in reversed(anim_comps)]):
        st = dict(zip(reversed(combo_ids), states))
        combo_totals.append(res[label(st)]["total"])
    for c in comps:
        if c.get("wall_delta_placeholder"):
            require(c["id"] not in combo_ids, "component %s: a wall placeholder on a measured component" % c["id"])
            state_wall[c["id"]] = [0, int(c["wall_delta_placeholder"])] + [0] * (c["n_states"] - 2)
    log("wall: MAIN %d; %s; %s" % (
        base, ", ".join("%s %d" % (k, v["total"]) for k, v in res.items()),
        "additive model holds on %d measured combination(s)" % len(combos) if not not_additive else
        "NOT additive (%s): the installer uses the exact per-combination table" % "; ".join(not_additive)))
    return {"base": base, "state_wall": state_wall, "measured": {k: v["total"] for k, v in res.items()},
            "combo_comps": combo_ids if anim_comps else [], "combo_totals": combo_totals if anim_comps else [],
            "additive": not not_additive, "detail": res}


def check_forced(src: dict, comps: list, w: dict, ercap_only: dict) -> dict:
    """2026-10-03 (Luka's DMN + Wylder decision: DMN + NRM ships NRM 0.2 WITH Wylder and the installer adds
    ERCapacityExpansion for it). Over the measured per-combination table (w['combo_comps'] / w['combo_totals'], the
    installer's CurrentWallTotal reads it the same way) and the catalog's D rules (a and b together need the DLL
    component; the installer forces it and shows the rule's text as the reason):
      - every combination that uses an ERCap-only DMN layer (rcinputs: ercap_only 'plain' / 'nrm') measures over
        wall.limit_without_dll, so the installer forces the DLL for it (such a layer is never installed without it),
        and a D rule holds on it (the reason the Options page shows next to the locked check box);
      - a D rule holds only on combinations over that limit (it never forces the DLL for a selection that fits) and
        names two animation options (measured per combination);
      - no combination is over wall.limit_with_dll.
    A combination over the limit that no D rule names is allowed (one option alone cannot be a D rule): the installer
    forces the DLL with its generic wall reason; it is logged.
    -> {"over": [labels], "ercap_only_combos": [labels], "d_rules": n, "generic_reason": [labels]}"""
    lim, lim_dll = int(src["wall"]["limit_without_dll"]), int(src["wall"]["limit_with_dll"])
    ids = list(w.get("combo_comps") or [])
    cmap = {c["id"]: c for c in comps}
    drules = [r for r in src["rules"] if r["kind"] == "D"]
    prod = {c.get("product"): c["id"] for c in comps if c.get("product") and c["kind"] != "X"}
    dmn_id, nrm_id = prod.get("dmn"), prod.get("nrm")
    for r in drules:
        require(r["a"] in ids and r["b"] in ids, "rule D %s/%s: both options must change the animation binders (the "
                "measured per-combination table covers %s)" % (r["a"], r["b"], ids))
    if ercap_only:
        require(dmn_id in ids, "an ERCap-only DMN layer, but DMN is not in the measured animation table %s" % ids)
    if not ids:
        return {"over": [], "ercap_only_combos": [], "d_rules": len(drules), "generic_reason": []}

    def label(st):
        on = ["%s=%d" % (k, v) for k, v in sorted(st.items()) if v]
        return "main" + ("+" + "+".join(on) if on else "")

    over, eo_combos, generic, bad = [], [], [], []
    for states in itertools.product(*[range(cmap[i]["n_states"]) for i in reversed(ids)]):
        st = dict(zip(reversed(ids), states))
        idx, radix = 0, 1
        for i in ids:                         # the first animation option's state counts fastest (as the installer)
            idx += st[i] * radix
            radix *= cmap[i]["n_states"]
        total = w["combo_totals"][idx]
        lab = "%s (%d)" % (label(st), total)
        is_over = total > lim
        dmatch = [r["text"] for r in drules if cmap[r["a"]]["codes"][st[r["a"]]] in r["a_states"]
                  and cmap[r["b"]]["codes"][st[r["b"]]] in r["b_states"]]
        dmn_on = st.get(dmn_id, 0) >= 1
        nrm_on = st.get(nrm_id, 0) >= 1 if nrm_id in st else False
        uses_eo = dmn_on and ("nrm" if nrm_on else "plain") in ercap_only
        if total > lim_dll:
            bad.append("%s is over the DLL's limit %d too" % (lab, lim_dll))
        if is_over:
            over.append(lab)
            if not dmatch:
                generic.append(lab)
        if uses_eo:
            eo_combos.append(lab)
            if not is_over:
                bad.append("%s uses the ERCap-only DMN layer but measures under %d: the installer would install it "
                           "WITHOUT the DLL" % (lab, lim))
            if not dmatch:
                bad.append("%s uses the ERCap-only DMN layer but no D rule names it (the Options page would show no "
                           "reason for the locked DLL)" % lab)
        if dmatch and not is_over:
            bad.append("%s fits under %d, but the D rule '%s' would force the DLL for it" % (lab, lim, dmatch[0]))
    require(not bad, "animation wall / D rules: %s" % "; ".join(bad))
    log("wall: the DLL is forced for %d combination(s) of %s: %s%s; ERCap-only DMN layer(s) %s used by %s" % (
        len(over), ids, ", ".join(over) or "none",
        " (no D rule, generic reason: %s)" % ", ".join(generic) if generic else " (each named by a D rule)",
        sorted(ercap_only) or "none", ", ".join(eo_combos) or "none"))
    return {"over": over, "ercap_only_combos": eo_combos, "d_rules": len(drules), "generic_reason": generic}

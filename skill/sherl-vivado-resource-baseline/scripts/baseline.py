#!/usr/bin/env python3
"""Collect an existing design, summarize reports, or compare two evidence sets."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

METRICS = ["LUT", "LogicLUT", "LUTRAM", "SRL", "FF", "RAMB36", "RAMB18", "URAM", "DSP", "BRAM36eq"]
ALIASES = {"Total LUTs": "LUT", "Logic LUTs": "LogicLUT", "LUTRAMs": "LUTRAM", "SRLs": "SRL",
           "FFs": "FF", "RAMB36": "RAMB36", "RAMB18": "RAMB18", "URAM": "URAM", "DSP Blocks": "DSP"}
SOURCE_EXT = {".v", ".sv", ".vh", ".svh", ".vhd", ".vhdl", ".xdc", ".xci", ".xcix", ".bd",
              ".bda", ".mem", ".coe", ".mif", ".xpr", ".tcl"}


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def file_record(path):
    p = Path(path).resolve(strict=True)
    return {"path": str(p), "bytes": p.stat().st_size, "sha256": digest(p)}


def debug_configuration(source_files):
    """Compare debug parameters without treating XCI output paths as hardware changes."""
    profiles = []
    for path in source_files:
        if path.suffix.lower() != ".xci":
            continue
        values = {next((v for k, v in e.attrib.items() if k.endswith("referenceId")), ""): "".join(e.itertext())
                  for e in ET.parse(path).iter() if e.tag.endswith("configurableElementValue")}
        if any(k in values for k in ["PARAM_VALUE.C_NUM_OF_PROBES", "PARAM_VALUE.C_NUM_PROBE_IN", "PARAM_VALUE.C_NUM_PROBE_OUT"]):
            profiles.append({"name": path.stem, "parameters": {k: v for k, v in sorted(values.items()) if k.startswith("PARAM_VALUE.C_")}})
    return sorted(profiles, key=lambda x: x["name"])


def dump(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def table(path):
    if not path.exists():
        return []
    with path.open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def hierarchy(path):
    """Preserve Vivado hierarchy ownership; never add inclusive parent/child rows."""
    rows, stack, columns = [], {}, None
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if not line.startswith("|"):
            continue
        raw = line.split("|")[1:-1]
        fields = [v.strip() for v in raw]
        if fields[:2] == ["Instance", "Module"]:
            columns = fields
            continue
        if not columns or len(fields) != len(columns):
            continue
        try:
            values = {ALIASES.get(k, k): int(v.replace(",", "")) for k, v in zip(columns[2:], fields[2:])}
        except ValueError:
            continue
        if not {"LUT", "FF", "RAMB36", "RAMB18", "DSP"}.issubset(values):
            raise ValueError(f"Unsupported utilization columns: {columns}")
        depth = (len(raw[0]) - len(raw[0].lstrip()) - 1) // 2
        own = fields[0].startswith("(") and fields[0].endswith(")")
        if own:
            if depth - 1 not in stack:
                raise ValueError(f"Self row has no parent: {line}")
            instance = stack[depth - 1]
        else:
            if depth > 1 and depth - 1 not in stack:
                raise ValueError(f"Hierarchy skipped a parent: {line}")
            instance = fields[0] if depth <= 1 else stack[depth - 1] + "/" + fields[0]
            stack[depth] = instance
            for deeper in list(stack):
                if deeper > depth:
                    del stack[deeper]
        values["BRAM36eq"] = values["RAMB36"] + values["RAMB18"] / 2
        rows.append({"Path": instance, "Depth": depth - 1 if own else depth,
                     "Scope": "self" if own else "inclusive", "Module": fields[1], **values})
    if not rows or rows[0]["Depth"] != 0 or rows[0]["Scope"] != "inclusive":
        raise ValueError("No complete top hierarchy row found")
    keys = [(r["Path"], r["Scope"]) for r in rows]
    if len(keys) != len(set(keys)):
        raise ValueError("Duplicate path/scope rows; refusing an ambiguous comparison")
    return rows


def official_timing(path):
    text = path.read_text(encoding="utf-8-sig")
    part = text.split("| Design Timing Summary", 1)[-1]
    for line in part.splitlines():
        vals = line.split()
        if len(vals) == 12:
            try:
                nums = [float(x) for x in vals]
            except ValueError:
                continue
            keys = ["WNS_ns", "TNS_ns", "setup_failing_endpoints", "setup_total_endpoints",
                    "WHS_ns", "THS_ns", "hold_failing_endpoints", "hold_total_endpoints",
                    "WPWS_ns", "TPWS_ns", "pulse_width_failing_endpoints", "pulse_width_total_endpoints"]
            return {k: int(n) if "endpoints" in k else n for k, n in zip(keys, nums)}
    return None


def report_context(path):
    text = path.read_text(encoding="utf-8-sig")
    result = {}
    for name in ["Tool Version", "Design", "Device", "Design State"]:
        m = re.search(r"^\| " + name + r"\s*:\s*(.+)$", text, re.M)
        result[name] = m.group(1).strip() if m else None
    return result


def whole_utilization(path):
    """Use the official whole-design table, including actual occupied CLBs."""
    names = {"CLB LUTs": "LUT", "Slice LUTs": "LUT", "CLB Registers": "FF", "Slice Registers": "FF",
             "DSPs": "DSP", "Block RAM Tile": "BRAM36eq", "URAM": "URAM", "CLB": "Occupied_CLB", "Slice": "Occupied_Slice"}
    result = {metric: None for metric in set(names.values())}
    if not path.exists():
        return result
    columns = None
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if not line.startswith("|"):
            continue
        fields = [x.strip() for x in line.split("|")[1:-1]]
        if fields and fields[0] == "Site Type" and {"Used", "Available", "Util%"}.issubset(fields):
            columns = fields
            continue
        if not fields or not columns or len(fields) != len(columns):
            continue
        name = fields[0].rstrip("*")
        if name not in names:
            continue
        row = dict(zip(columns, fields))
        values = {"site_type": name}
        for label, column in [("used", "Used"), ("available", "Available"), ("util_percent", "Util%")]:
            try:
                values[label] = float(row[column].replace(",", ""))
            except ValueError:
                values[label] = None
        result[names[name]] = values
    return result


def shown(value):
    return "unknown" if value is None else f"{value:g}"


def write_csv(path, rows, fields):
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def summarize(directory, write=True):
    directory = directory.resolve(strict=True)
    rows = hierarchy(directory / "hierarchy.rpt")
    manifest_path = directory / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else None
    metadata = {r["key"]: r["value"] for r in table(directory / "metadata.tsv")}
    status = table(directory / "report_status.tsv")
    paths = table(directory / "path_scope_summary.tsv")
    for row in paths:
        row["worst_slack_ns"] = float(row["worst_slack_ns"]) if row["worst_slack_ns"] else None
        for k in ["negative_paths", "unique_endpoints", "cap_reached"]:
            row[k] = int(row[k])
    context = report_context(directory / "hierarchy.rpt")
    utilization = whole_utilization(directory / "utilization.rpt")
    warnings = []
    if not manifest:
        warnings.append("No collection manifest: report-only import; source/artifact binding is unknown.")
    elif manifest.get("requested_stage", "").lower() != (context.get("Design State") or "").lower():
        warnings.append("Requested stage differs from the report's actual Design State; use the actual state for comparison.")
    if any(r["status"] not in {"OK", "EMPTY"} for r in status):
        warnings.append("Some reports failed; inspect report_status.tsv before making a complete-review claim.")
    if any(r["cap_reached"] for r in paths):
        warnings.append("Negative-path query reached its cap; endpoint coverage is incomplete.")
    if metadata.get("hierarchy_depth_limit") and max(r["Depth"] for r in rows) >= int(metadata["hierarchy_depth_limit"]):
        warnings.append("Hierarchy reached its depth limit; increase depth before calling it complete.")
    for metric in ["LUT", "FF", "DSP", "BRAM36eq", "URAM"]:
        if utilization[metric] and utilization[metric]["used"] is not None and metric in rows[0] and utilization[metric]["used"] != rows[0][metric]:
            warnings.append(f"Whole utilization and hierarchy disagree for {metric}; check that reports come from the same design.")
    summary = {"schema": 1, "directory": str(directory), "context": context, "metadata": metadata,
               "official_timing": official_timing(directory / "timing_summary.rpt"), "path_scopes": paths,
               "clocks": table(directory / "clocks.tsv"), "report_status": status, "top_resources": rows[0],
               "whole_utilization": utilization, "summarizer": file_record(__file__),
               "hierarchy_rows": len(rows), "manifest_sha256": digest(manifest_path) if manifest else None,
               "warnings": warnings,
               "notes": ["Inclusive rows already contain children; self rows only contain directly owned logic.",
                         "TNS/THS/TPWS come only from the official timing summary, never a sum of rounded queried slacks.",
                         "PHY scopes are register-to-register and top-I/O boundary queries. Unconstrained/excepted paths remain outside positive-slack claims.",
                         "Co-collected source/bit hashes do not by themselves prove they produced this DCP."]}
    fields = list(dict.fromkeys(k for r in rows for k in r))
    if write:
        write_csv(directory / "complete_resource_hierarchy.csv", rows, fields)
        dump(directory / "summary.json", summary)
    lines = ["# Vivado 资源与时序基准", "", "## 1. 设计与核验范围", "",
             f"- 设计：`{context['Design']}`；器件：`{context['Device']}`。",
             f"- 工具：{context['Tool Version']}；网表状态：{context['Design State']}。",
             f"- 完整层级表：`complete_resource_hierarchy.csv`（{len(rows)} 行，保留 inclusive/self）。",
             "- 原始约束、未约束路径、CDC 和异常覆盖须按实际生成的报告单独审查。", "",
             "## 2. 整机资源", "", "| 资源 | 使用量 | 可用量 | 利用率 % |", "| :--- | ---: | ---: | ---: |"]
    metrics = ["LUT", "FF", "DSP", "BRAM36eq", "URAM", "Occupied_Slice" if utilization["Occupied_Slice"] else "Occupied_CLB"]
    for metric in metrics:
        value = utilization[metric] or {}
        used = value.get("used", rows[0].get(metric))
        lines.append(f"| {metric} | {shown(used)} | {shown(value.get('available'))} | {shown(value.get('util_percent'))} |")
    lines += ["", "占用 CLB／Slice 取官方整机报告，不由 LUT 数推算，也不虚构到模块层级。父层已包含子层，不能相加。改变调试核、约束、策略、网表阶段时，资源差不全部归因于算法优化。", "",
              "## 3. 时序", ""]
    if summary["official_timing"]:
        t = summary["official_timing"]
        lines += ["| 范围 | 最差裕量 ns | 总负裕量 ns | 失败终点 |", "| :--- | ---: | ---: | ---: |"]
        for label, w, total, count in [("建立", "WNS_ns", "TNS_ns", "setup_failing_endpoints"),
                                       ("保持", "WHS_ns", "THS_ns", "hold_failing_endpoints"),
                                       ("脉宽", "WPWS_ns", "TPWS_ns", "pulse_width_failing_endpoints")]:
            lines.append(f"| {label} | {t[w]} | {t[total]} | {t[count]} |")
    else:
        lines.append("官方摘要未解析成功；直接查 `timing_summary.rpt`，不能据此宣称通过。")
    lines += ["", "分区查询见 `path_scope_summary.tsv`：whole、phy_internal、into_phy、out_of_phy。`negative_paths.tsv` 按 `-nworst 1` 保留代表负路径／失败终点视图，不枚举全部组合路径；上限命中时端点覆盖也不完整。", "",
              "## 4. 证据与限制", "", "- `manifest.json` 记录 DCP／工程、附带 bit、源码、工具及脚本哈希；若未提供本次构建输入清单，只说明一同收集，不能证明源码与 DCP 匹配。",
              "- 正时序只覆盖已约束且未被例外移除的路径；CDC 报告的 Critical 不因正 WNS 自动消失。"]
    lines += [f"- {w}" for w in warnings]
    if write:
        (directory / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return summary


def collect(args):
    out = args.out.resolve()
    if out.exists():
        raise ValueError("Output must be a fresh directory; existing evidence is never overwritten")
    if any(out == root.resolve() or root.resolve() in out.parents for root in args.source_root):
        raise ValueError("Output cannot be inside a --source-root; collection must not write into protected source trees")
    vivado = str(Path(shutil.which(args.vivado) or args.vivado).resolve(strict=True))
    if any(not p.is_dir() for p in args.source_root):
        raise ValueError("Each --source-root must be an existing directory")
    source_files = sorted({p.resolve() for root in args.source_root for p in root.resolve(strict=True).rglob("*")
                           if p.is_file() and p.suffix.lower() in SOURCE_EXT})
    sources = [file_record(p) for p in source_files]
    inputs = {"dcp" if args.dcp else "project": file_record(args.dcp or args.project)}
    if args.project:
        project = args.project.resolve(strict=True)
        run = next((e for e in ET.parse(project).iter("Run") if e.get("Id") == args.run), None)
        if run is None or not run.get("Dir"):
            raise ValueError("Run directory is not recorded in this XPR; use an explicit --dcp instead")
        run_dir = run.get("Dir").replace("$PRUNDIR", str(project.with_suffix(".runs"))).replace("$PPRDIR", str(project.parent))
        if "$" in run_dir:
            raise ValueError("Unsupported XPR run-directory macro; use an explicit --dcp instead")
        run_dir = Path(run_dir)
        if not run_dir.is_absolute():
            run_dir = project.parent / run_dir
        checkpoints = sorted(run_dir.glob("*.dcp"))
        if not checkpoints:
            raise ValueError("No completed checkpoint found for this run; collection never builds it")
        for checkpoint in checkpoints:
            inputs["run_dcp." + checkpoint.name] = file_record(checkpoint)
    for item in args.artifact:
        label, sep, value = item.partition("=")
        if not sep or label in inputs:
            raise ValueError("Artifact must be a unique label=path")
        inputs[label] = file_record(value)
    if args.build_input_manifest:
        inputs["build_input_manifest"] = file_record(args.build_input_manifest)
    tool = file_record(vivado)
    script = Path(__file__).resolve().with_name("collect.tcl")
    out.mkdir(parents=True)
    command = [vivado, "-mode", "batch", "-nojournal", "-nolog", "-source", str(script), "-tclargs",
               "-out", str(out), "-phy", args.phy or "", "-cap", str(args.cap), "-depth", str(args.depth),
               "-audits", str(int(args.audits)), "-run", args.run,
               "-dcp" if args.dcp else "-project", str((args.dcp or args.project).resolve(strict=True))]
    manifest = {"schema": 1, "collected_at_utc": datetime.now(timezone.utc).isoformat(),
                "requested_stage": args.stage, "command": command, "inputs": inputs, "source_files": sources,
                "tool_launcher": tool, "collector": file_record(script), "wrapper": file_record(__file__),
                "debug_configuration": debug_configuration(source_files) if source_files else None,
                "provenance": "co-collected-only; verify supplied build-input manifest separately"}
    dump(out / "manifest.json", manifest)
    with (out / "vivado.log").open("w") as log:
        result = subprocess.run(command, cwd=out, stdout=log, stderr=subprocess.STDOUT, check=False)
    changed = [r["path"] for r in [*inputs.values(), *sources] if not Path(r["path"]).exists() or digest(r["path"]) != r["sha256"]]
    manifest["input_content_changed_during_collection"] = changed
    manifest["returncode"] = result.returncode
    manifest["outputs"] = [file_record(p) for p in sorted(out.iterdir()) if p.is_file() and p.name != "manifest.json"]
    dump(out / "manifest.json", manifest)
    if result.returncode or changed:
        raise RuntimeError(f"Collection failed or inputs changed: code={result.returncode}; changed={changed}; inspect {out / 'vivado.log'}")
    result = summarize(out)
    print(f"COLLECTED {out}; hierarchy_rows={result['hierarchy_rows']}; warnings={len(result['warnings'])}")


def compare(args):
    old, new = [summarize(p, write=False) for p in [args.old, args.new]]
    old_rows, new_rows = [hierarchy(p / "hierarchy.rpt") for p in [args.old, args.new]]
    indexes = [{(r["Path"], r["Scope"]): r for r in rows} for rows in [old_rows, new_rows]]
    conditions = {"tool": (old["context"]["Tool Version"], new["context"]["Tool Version"]),
                  "part": (old["context"]["Device"], new["context"]["Device"]),
                  "netlist_state": (old["context"]["Design State"], new["context"]["Design State"]),
                  "clocks": (old["clocks"] or None, new["clocks"] or None),
                  "run_configuration": tuple({k: v for k, v in s["metadata"].items() if k.startswith("run.") and k != "run.STATUS"} or None for s in [old, new])}
    # Identical file names with different XDC hashes are a changed constraint set.
    manifests = [json.loads((p / "manifest.json").read_text()) if (p / "manifest.json").exists() else {} for p in [args.old, args.new]]
    conditions["constraints"] = tuple(sorted((Path(r["path"]).name, r["sha256"]) for r in m.get("source_files", []) if Path(r["path"]).suffix.lower() == ".xdc") or None for m in manifests)
    conditions["debug_configuration"] = tuple(m.get("debug_configuration") for m in manifests)
    debug_roots = []
    for collection in [old_rows, new_rows]:
        candidates = [r for r in collection if r["Scope"] == "inclusive" and re.match(r"^(ila|vio)(?:_|$)", r["Module"], re.I)]
        debug_roots.append(sorted((r["Path"], r["Module"]) for r in candidates
                                  if not any(r["Path"].startswith(p["Path"] + "/") for p in candidates if p is not r)))
    conditions["debug_netlist_roots"] = tuple(debug_roots)
    checks = {k: {"old": a, "new": b, "status": "unknown" if a is None or b is None else "same" if a == b else "different"}
              for k, (a, b) in conditions.items()}
    rows = []
    for key in sorted(indexes[0].keys() | indexes[1].keys()):
        a, b = [idx.get(key) for idx in indexes]
        row = {"Path": key[0], "Scope": key[1], "Status": "matched" if a and b else "old_only" if a else "new_only"}
        for metric in METRICS:
            row["Old_" + metric], row["New_" + metric] = [r.get(metric) if r else None for r in [a, b]]
            row["Delta_" + metric] = b[metric] - a[metric] if a and b and metric in a and metric in b else None
        rows.append(row)
    out = args.out.resolve()
    if out.exists():
        raise ValueError("Comparison output must be a fresh directory")
    out.mkdir(parents=True)
    write_csv(out / "hierarchy_comparison.csv", rows, list(rows[0]))
    resource_comparison = {}
    for metric in ["LUT", "FF", "DSP", "BRAM36eq", "URAM", "Occupied_CLB", "Occupied_Slice"]:
        a, b = [(s["whole_utilization"][metric] or {}) for s in [old, new]]
        resource_comparison[metric] = {"old": a or None, "new": b or None}
        for label in ["used", "util_percent"]:
            resource_comparison[metric]["delta_" + label] = b[label] - a[label] if a.get(label) is not None and b.get(label) is not None else None
    result = {"old": str(args.old.resolve()), "new": str(args.new.resolve()), "conditions": checks,
              "whole_resource_comparison": resource_comparison, "comparer": file_record(__file__),
              "input_binding": {label: {name: file_record(path / name) for name in ["hierarchy.rpt", "timing_summary.rpt", "manifest.json"] if (path / name).exists()}
                                for label, path in [("old", args.old), ("new", args.new)]},
              "timing": {"old": old["official_timing"], "new": new["official_timing"]},
              "matched_rows": sum(r["Status"] == "matched" for r in rows),
              "notes": ["Delta = new - old. Missing paths stay null; a renamed or flattened module is not zero resources.",
                        "No parent/child summation or automatic path aliasing is performed.",
                        "Identical listed conditions do not prove debug configuration or build provenance is identical; inspect source/IP manifests."]}
    dump(out / "comparison.json", result)
    lines = ["# 资源与时序前后对照", "", "## 1. 比较条件", "", "| 条件 | 状态 |", "| :--- | :--- |"]
    lines += [f"| {k} | {v['status']} |" for k, v in checks.items()]
    lines += ["", "完整条件值、两次官方时序见 `comparison.json`。缺少 run 配置或源码／调试核证据时，不能宣称同条件优化收益。", "", "## 2. 整机资源", "",
              "| 资源 | 旧使用量 | 新使用量 | 新减旧 | 旧利用率 % | 新利用率 % |", "| :--- | ---: | ---: | ---: | ---: | ---: |"]
    occupied = "Occupied_Slice" if any(s["whole_utilization"]["Occupied_Slice"] for s in [old, new]) else "Occupied_CLB"
    for metric in ["LUT", "FF", "DSP", "BRAM36eq", "URAM", occupied]:
        a, b = [(s["whole_utilization"][metric] or {}) for s in [old, new]]
        av, bv = a.get("used", old_rows[0].get(metric)), b.get("used", new_rows[0].get(metric))
        delta = bv - av if av is not None and bv is not None else None
        lines.append(f"| {metric} | {shown(av)} | {shown(bv)} | {shown(delta)} | {shown(a.get('util_percent'))} | {shown(b.get('util_percent'))} |")
    lines += ["", "## 3. 层级与限制", "", f"精确路径与范围匹配 {result['matched_rows']} 行；全部模块、自身资源和增减见 `hierarchy_comparison.csv`。父层包含子层，不能相加；路径消失不等于资源归零。",
              "", "调试核删除、约束／策略变化、不同网表阶段、完整重综合后的层级归属变化，都必须与算法结构收益分开解释。局部正裕量不代表整机时序通过，也不代表板测通过。"]
    (out / "comparison.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"COMPARED {out}; matched_rows={result['matched_rows']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    c = sub.add_parser("collect", help="Open only an existing checkpoint/completed run; never launch a run")
    group = c.add_mutually_exclusive_group(required=True)
    group.add_argument("--dcp", type=Path)
    group.add_argument("--project", type=Path)
    c.add_argument("--run", default="impl_1")
    c.add_argument("--vivado", default="vivado")
    c.add_argument("--stage", required=True, choices=["synthesized", "placed", "routed"])
    c.add_argument("--out", type=Path, required=True)
    c.add_argument("--phy", help="Exact instance path, no top-name prefix or glob")
    c.add_argument("--source-root", type=Path, action="append", default=[])
    c.add_argument("--artifact", action="append", default=[], help="label=/absolute/path (e.g. bit=...)")
    c.add_argument("--build-input-manifest", type=Path, help="Retained build-input hashes; collected as evidence, not blindly trusted")
    c.add_argument("--audits", action="store_true", help="Also export CDC, exceptions, bus skew, DRC and methodology")
    c.add_argument("--cap", type=int, default=200000)
    c.add_argument("--depth", type=int, default=64)
    s = sub.add_parser("summarize", help="Parse an existing report directory without running Vivado")
    s.add_argument("directory", type=Path)
    x = sub.add_parser("compare", help="Compare complete same-stage evidence directories without rerunning implementation")
    x.add_argument("--old", type=Path, required=True)
    x.add_argument("--new", type=Path, required=True)
    x.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.action == "collect":
        if args.cap < 1 or args.depth < 1:
            parser.error("cap and depth must be positive")
        collect(args)
    elif args.action == "summarize":
        result = summarize(args.directory)
        print(f"SUMMARIZED hierarchy_rows={result['hierarchy_rows']}; warnings={len(result['warnings'])}")
    else:
        compare(args)


if __name__ == "__main__":
    main()

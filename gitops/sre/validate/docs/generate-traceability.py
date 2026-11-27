#!/usr/bin/env python3

from pathlib import Path
import re
import hashlib
import subprocess

ROOT = Path(__file__).resolve().parents[4]
BASE = ROOT / "gitops/sre/validate"
OUT = BASE / "docs/code-transitivity.md"

groups = [
    (
        "Interactive assessment controls",
        [
            ("grafana-plugin/src/MissionControlPanel.tsx",
             "new AssessmentAPI",
             "Construct the API client using the Grafana transport."),

            ("grafana-plugin/src/ControlPanel.tsx",
             "function start(",
             "Construct the bounded assessment request."),

            ("grafana-plugin/src/ControlPanel.tsx",
             "function stop(",
             "Stop only the identified active assessment."),

            ("grafana-plugin/src/api.ts",
             "'/api/v1/start'",
             "Send the start request to the resource endpoint."),

            ("grafana-plugin/src/api.ts",
             "'/api/v1/stop'",
             "Send the assessment identity for cancellation."),

            ("grafana-plugin/src/transport.ts",
             "RESOURCE_BASE",
             "Route browser requests through the Grafana app plugin."),
        ]
    ),
    (
        "Workload instrumentation and recovery",
        [
            ("k6/product-listing.js",
             "const profiles =",
             "Define the Normal and 11:11 load stages."),

            ("k6/product-listing.js",
             "new Trend(",
             "Declare the product-listing latency metric."),

            ("k6/product-listing.js",
             "new Rate(",
             "Declare the content-validation failure metric."),

            ("k6/product-listing.js",
             "thresholds:",
             "Configure k6 assessment objectives."),

            ("k6/product-listing.js",
             "assessment_run:",
             "Attach the unique assessment identity."),

            ("k6/product-listing.js",
             "const phase =",
             "Distinguish load from recovery observations."),

            ("k6/product-listing.js",
             "http.get(",
             "Execute the bounded catalog request."),

            ("k6/product-listing.js",
             "productLatency.add(",
             "Record measured request duration."),

            ("k6/product-listing.js",
             "productFailure.add(",
             "Record content-validation failures."),

            ("controller/telemetry.py",
             "def recovery_observation(",
             "Read run-specific recovery telemetry."),

            ("controller/telemetry.py",
             'f"1000 * max(',
             "Convert exported latency from seconds to milliseconds."),

            ("controller/telemetry.py",
             "min(timestamp(",
             "Check freshness of underlying Prometheus samples."),
        ]
    ),
    (
        "Persistent state and concurrency",
        [
            ("controller/state.py",
             "def initial_state(",
             "Define the initial lifecycle contract."),

            ("controller/state.py",
             "def read(",
             "Read persisted state and Kubernetes resourceVersion."),

            ("controller/state.py",
             "resource_version=resource_version",
             "Supply the optimistic concurrency precondition."),

            ("controller/state.py",
             "replace_namespaced_config_map(",
             "Persist state through the Kubernetes API."),

            ("controller/state.py",
             "exc.status == 409",
             "Detect conflicting concurrent updates."),
        ]
    ),
    (
        "Live commentary and dashboard synchronization",
        [
            ("grafana-plugin/src/ControlPanel.tsx",
             "POLL_INTERVAL_MS =",
             "Define the controller polling interval."),

            ("grafana-plugin/src/ControlPanel.tsx",
             "locationService.partial(",
             "Synchronize Grafana with the active assessment identity."),

            ("grafana-plugin/src/commentary.ts",
             "function describeAssessment(",
             "Translate controller state into lifecycle commentary."),

            ("grafana-plugin/src/commentary.ts",
             "function describeRecovery(",
             "Require verified recovery evidence before reporting success."),

            ("grafana-plugin/src/LiveTelemetry.tsx",
             "frame.refId === refId",
             "Match Grafana query references to presentation metrics."),

            ("grafana-plugin/src/LiveTelemetry.tsx",
             "const fresh =",
             "Distinguish recent samples from historical samples."),

            ("grafana-plugin/src/MetricExplanationGrid.tsx",
             "Object.entries(metricDefinitions)",
             "Render all metric explanation definitions."),

            ("grafana-plugin/src/MetricExplanation.tsx",
             "aria-expanded={visible}",
             "Expose interactive explanation visibility."),
        ]
    ),
]

output = [
    "# Capstone — SRE Code Transitivity",
    "",
    "Generated from the current working tree.",
    "",
    "Source references establish implementation traceability, "
    "not successful shared-cluster deployment.",
    "",
    "## End-to-end architecture",
    "",
    "```mermaid",
    "flowchart TD",
    '    A["Grafana control panel"] --> B["AssessmentAPI"]',
    '    B --> C["Grafana resource transport"]',
    '    C --> D["Go backend authorization"]',
    '    D --> E["Controller API"]',
    '    E --> F["Lifecycle and preflight"]',
    '    F --> G["Kubernetes Job"]',
    '    G --> H["k6 production catalog workload"]',
    '    H --> I["Prometheus"]',
    '    I --> J["Grafana live telemetry"]',
    '    I --> K["Recovery evaluation"]',
    '    K --> L["Persistent assessment state"]',
    '    L --> A',
    '    L --> M{"Recurrence eligible?"}',
    '    M -->|Yes| F',
    '    M -->|No| N["Assessment history"]',
    "```",
    "",
]

missing = []
referenced = set()

for heading, entries in groups:

    output.extend(["## " + heading, ""])

    for filename, anchor, explanation in entries:

        path = BASE / filename

        if not path.exists():
            missing.append(filename)
            continue

        lines = path.read_text().splitlines()

        matches = [
            index for index, line in enumerate(lines, 1)
            if anchor in line
        ]

        if len(matches) != 1:
            missing.append(
                f"{filename}: {anchor}: "
                f"{len(matches)} matches"
            )
            continue

        line_number = matches[0]
        referenced.add(path)

        relative = "../" + filename

        output.extend([
            f"### `{filename}:{line_number}`",
            "",
            f"[Inspect source]({relative}#L{line_number})",
            "",
            explanation,
            "",
            "```",
            lines[line_number - 1].strip(),
            "```",
            "",
        ])

if missing:
    raise SystemExit(
        "Unresolved source references:\n"
        + "\n".join(missing)
    )

output.extend([
    "## Source integrity",
    "",
    "| Source file | SHA-256 |",
    "|---|---|",
])

for path in sorted(referenced):
    digest = hashlib.sha256(
        path.read_bytes()
    ).hexdigest()

    output.append(
        f"| `{path.relative_to(ROOT)}` | `{digest}` |"
    )

output.extend([
    "",
    "## Evidence boundaries",
    "",
    "- Source inspection does not establish live execution.",
    "- Plugin signing and installation require validation.",
    "- Actual alert delivery requires observed notification evidence.",
    "- HPA scaling must be demonstrated using observed replica changes.",
    "- Recovery must be supported by fresh controller telemetry.",
    "- Production assessment execution requires authorized deployment.",
    "",
])

OUT.write_text("\n".join(output))

print("Generated:", OUT.relative_to(ROOT))
print("Referenced source files:", len(referenced))
print("Unresolved references: 0")

readme = ROOT / "gitops/sre/README.md"

start = "<!-- BEGIN GENERATED SRE TRACEABILITY -->"
end = "<!-- END GENERATED SRE TRACEABILITY -->"

section = f"""
{start}

## Interactive SRE assessment — code traceability

See [Code Transitivity](validate/docs/code-transitivity.md)
for source-level syntax, exact line references,
architecture and implementation evidence boundaries.

{end}
"""

text = readme.read_text()

if start in text:
    assert end in text

    text = re.sub(
        re.escape(start) + r".*?" + re.escape(end),
        lambda _: section.strip(),
        text,
        flags=re.S,
        count=1
    )
else:
    text = text.rstrip() + "\n\n" + section

readme.write_text(text)

print("PASS: legacy SRE README preserved")

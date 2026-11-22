#!/usr/bin/env bash
set -euo pipefail

TAG_KEY="${TAG_KEY:-Project}"
TF_DIRS=("." "github-oidc-bootstrap")

echo "================================================================================"
echo " Terraform-Provisioned AWS Resource & '${TAG_KEY}' Tag Audit"
echo "================================================================================"

for dir in "${TF_DIRS[@]}"; do
  if [ ! -d "${dir}" ] || ! find "${dir}" -maxdepth 1 -name "*.tf" | grep -q .; then
    continue
  fi

  echo ""
  echo ">>> Scanning Terraform Directory: ${dir}"
  echo "--------------------------------------------------------------------------------"

  if [ ! -d "${dir}/.terraform" ]; then
    terraform -chdir="${dir}" init -input=false >/dev/null
  fi

  TF_STATE_JSON=$(terraform -chdir="${dir}" show -json 2>/dev/null || true)

  if [ -z "${TF_STATE_JSON}" ] || [ "${TF_STATE_JSON}" = "{}" ]; then
    echo "No state found in '${dir}'."
    continue
  fi

  TF_STATE_JSON="${TF_STATE_JSON}" python3 - "${TAG_KEY}" <<'PY'
import json, os, sys

tag_key = sys.argv[1]
raw = os.environ.get("TF_STATE_JSON", "")
if not raw.strip():
    print("Empty state JSON.")
    sys.exit(0)

state = json.loads(raw)
root = state.get("values", {}).get("root_module", {})
resources = []

def walk(mod, prefix=""):
    for r in mod.get("resources", []):
        if r.get("mode") == "managed" and r.get("type", "").startswith("aws_"):
            addr = f"{prefix}{r['type']}.{r['name']}"
            vals = r.get("values") or {}
            tags_all = vals.get("tags_all") if isinstance(vals.get("tags_all"), dict) else {}
            tags = vals.get("tags") if isinstance(vals.get("tags"), dict) else {}
            merged = {**tags_all, **tags}
            res_id = vals.get("id") or vals.get("arn") or vals.get("name") or "-"

            if tag_key in merged and merged[tag_key]:
                status = f"TAGGED ({tag_key}={merged[tag_key]})"
            elif "tags" in vals or "tags_all" in vals:
                status = f"UNTAGGED (missing {tag_key})"
            else:
                status = "NO_TAG_SUPPORT"

            resources.append((status, addr, str(res_id)))

    for child in mod.get("child_modules", []):
        c_addr = child.get("address", "")
        walk(child, f"{c_addr}.")

walk(root)

if not resources:
    print("No managed aws_* resources found in state.")
    sys.exit(0)

order = {"UNTAGGED": 0, "TAGGED": 1, "NO_TAG_SUPPORT": 2}
resources.sort(key=lambda x: (order.get(x[0].split()[0], 9), x[1]))

print(f"{'STATUS':<34} | {'TERRAFORM ADDRESS':<48} | {'AWS ID / ARN'}")
print("-" * 125)
for status, addr, res_id in resources:
    print(f"{status:<34} | {addr:<48} | {res_id}")

tagged_cnt = sum(1 for r in resources if r[0].startswith("TAGGED"))
untagged_cnt = sum(1 for r in resources if r[0].startswith("UNTAGGED"))
nosupp_cnt = sum(1 for r in resources if r[0].startswith("NO_TAG_SUPPORT"))

print("-" * 125)
print(f"Summary: Total={len(resources)} | Tagged={tagged_cnt} | Untagged={untagged_cnt} | No-Tag-Support={nosupp_cnt}")
PY
done
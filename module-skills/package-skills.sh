#!/usr/bin/env bash
# Packages the skill set for distribution:
#   dist/skills/<name>.zip           — one zip per skill (SKILL.md inside a
#                                      top-level <name>/ dir — the bundle shape
#                                      the Anthropic Skills API / claude.ai
#                                      skill upload and `pro module deploy`
#                                      skills both accept)
#   dist/module-skills.zip   — the whole Claude Code plugin
# Run from this directory: ./package-skills.sh
set -euo pipefail
cd "$(dirname "$0")"

rm -rf dist
mkdir -p dist/skills

find . -name .DS_Store -delete

for dir in skills/*/; do
  name="$(basename "$dir")"
  (cd skills && zip -q -r -X "../dist/skills/${name}.zip" "$name" -x "*/node_modules/*" -x "*/.DS_Store")
  echo "✓ dist/skills/${name}.zip"
done

zip -q -r -X dist/module-skills.zip .claude-plugin .mcp.json skills README.md -x "*/.DS_Store"
echo "✓ dist/module-skills.zip (Claude Code plugin bundle)"

echo
unzip -l dist/module-skills.zip | tail -2

#!/bin/zsh
# Heuristic guard against French / un-localized literals reaching the UI.
# ponytail: a grep, not a linter — catches the obvious regressions (accented words,
# panel prompts, French keywords in string literals), not every case. Run before release.
set -euo pipefail
cd "$(dirname "$0")/.."

# 1. String literals containing accented (French) characters — should go through tr()/t().
#    Strip // comments first (so accented text in comments doesn't count); allow the
#    displayName endonyms (Français) and the catalog file itself.
accented=$(grep -rnE '"[^"]*[éèêàùçôîâ]' RunCockpit --include='*.swift' \
  | sed -E 's://.*$::' \
  | grep -E '"[^"]*[éèêàùçôîâ]' \
  | grep -vE 'displayName|Localization\.swift' || true)

# 2. NSOpenPanel / alert text assigned a raw literal instead of tr(...).
panels=$(grep -rnE '\.(prompt|message|title)[[:space:]]*=[[:space:]]*"' RunCockpit --include='*.swift' || true)

fail=0
if [[ -n "$accented" ]]; then echo "✘ Accented literal not via tr():"; echo "$accented"; fail=1; fi
if [[ -n "$panels"  ]]; then echo "✘ Raw panel/alert literal (use tr()):"; echo "$panels"; fail=1; fi
[[ $fail -eq 0 ]] && echo "✓ i18n check passed"
exit $fail

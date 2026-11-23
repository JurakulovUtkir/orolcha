#!/bin/bash
# Claude Code hook'larini Orolcha'ga ulaydi: har hodisa 127.0.0.1:47811 ga yuboriladi.
# Mavjud hook'laringiz saqlanadi, qayta ishga tushirish xavfsiz (dublikat qo'shmaydi).
#
#   ./install-hooks.sh            qo'shish
#   ./install-hooks.sh --remove   olib tashlash
set -euo pipefail

command -v jq >/dev/null || { echo "jq kerak (macOS 15+ da bor, aks holda: brew install jq)"; exit 1; }

F="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$F")"
[[ -f "$F" ]] || echo '{}' > "$F"
cp "$F" "$F.bak-orolcha"

MODE=add
[[ "${1:-}" == "--remove" ]] && MODE=remove

# Ilova yopiq bo'lsa ham Claude'ni sekinlashtirmaydi: 1 soniya chegarasi va doim muvaffaqiyatli chiqish.
CMD='curl -s -m 1 -o /dev/null -H "Expect:" -H "X-App: ${__CFBundleIdentifier:-}" --data-binary @- http://127.0.0.1:47811/claude || true'

jq --arg cmd "$CMD" --arg mode "$MODE" '
  def ours: (.hooks // []) | any(.command | contains("127.0.0.1:47811"));
  def entry($tool): (if $tool then {matcher: "*"} else {} end)
                    + {hooks: [{type: "command", command: $cmd, timeout: 3}]};
  .hooks //= {}
  | reduce (["SessionStart", false], ["UserPromptSubmit", false], ["PreToolUse", true], ["PostToolUse", true],
            ["Notification", false], ["Stop", false], ["PreCompact", false], ["SessionEnd", false]) as [$ev, $tool]
      (.; .hooks[$ev] = ((.hooks[$ev] // []) | map(select(ours | not))
                         + (if $mode == "add" then [entry($tool)] else [] end)))
  | .hooks |= with_entries(select(.value | length > 0))
' "$F.bak-orolcha" > "$F.tmp"

jq -e . "$F.tmp" >/dev/null && mv "$F.tmp" "$F"
echo "Tayyor ($MODE): $F  (zaxira: $F.bak-orolcha)"

#!/usr/bin/env bash
#
# build-local.sh — Build a standalone RunCockpit.app for PERSONAL use on this Mac.
# No Apple Developer Program / notarization required (ad-hoc signed).
#
# Usage:
#   scripts/build-local.sh              # produces build/RunCockpit.app
#   scripts/build-local.sh --dmg        # also produces build/RunCockpit.dmg
#   scripts/build-local.sh --adhoc      # force ad-hoc signing (for distribution
#                                       #   builds — see scripts/release.sh)
#
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=Release
OUT=build
DERIVED=$(mktemp -d)
trap 'rm -rf "$DERIVED"' EXIT

WANT_DMG=0
FORCE_ADHOC=0
for arg in "$@"; do
  case "$arg" in
    --dmg)   WANT_DMG=1 ;;
    --adhoc) FORCE_ADHOC=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

# --- Codesign identity auto-detection ------------------------------------
# A stable "Apple Development" identity yields a stable cdhash, so macOS TCC
# grants (Micro / Reconnaissance vocale / Accessibilité) PERSISTENT across
# rebuilds. Ad-hoc ("-") changes the cdhash every build → re-authorization.
# `security find-identity` exits 0 even with zero identities, so we parse its
# output rather than rely on $?.
# For DISTRIBUTION builds we force ad-hoc (--adhoc): an "Apple Development"
# identity is machine-bound and other Macs reject it more confusingly than a
# plain ad-hoc binary.
SIGN_IDENTITY="-"
SIGN_ADHOC=1
if [[ "$FORCE_ADHOC" == "0" ]]; then
  DEV_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Apple Development' \
    | head -n 1 \
    | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+[0-9A-F]+[[:space:]]+"(.*)"$/\1/')" || true
  if [[ -n "${DEV_IDENTITY}" ]]; then
    SIGN_IDENTITY="${DEV_IDENTITY}"
    SIGN_ADHOC=0
  fi
fi
if [[ "$SIGN_ADHOC" == "0" ]]; then
  echo "▶︎ Building $CONFIG — signing: ${SIGN_IDENTITY} (cdhash stable → TCC persiste)"
else
  echo "▶︎ Building $CONFIG — signing: ad-hoc (cdhash change à chaque build → re-grant TCC probable)"
fi
# -------------------------------------------------------------------------

xcodebuild \
  -project RunCockpit.xcodeproj \
  -scheme RunCockpit \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  CODE_SIGN_STYLE=Automatic \
  build | tail -1

APP="$DERIVED/Build/Products/$CONFIG/RunCockpit.app"
[ -d "$APP" ] || { echo "❌ Build product not found"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "$APP" "$OUT/"
echo "✅ App: $OUT/RunCockpit.app  (glissez-la dans /Applications)"

if [[ "$WANT_DMG" == "1" ]]; then
  echo "▶︎ Creating DMG…"
  hdiutil create -volname "RunCockpit" -srcfolder "$OUT/RunCockpit.app" -ov -format UDZO "$OUT/RunCockpit.dmg" >/dev/null
  echo "✅ DMG: $OUT/RunCockpit.dmg"
fi

cat <<'NOTE'

ℹ️  Premier lancement : clic droit sur RunCockpit.app → Ouvrir (contourne Gatekeeper
   pour une app non notarisée). Puis accordez les autorisations nécessaires dans
   Réglages → Autorisations.
NOTE

if [[ "$SIGN_ADHOC" == "1" ]]; then
  cat <<'NOTE'
   Note : signature ad-hoc → son empreinte change à chaque build, donc les
   autorisations peuvent être à re-accorder après une recompilation. Pour les
   stabiliser, connectez un Apple ID (gratuit) dans Xcode (Settings → Accounts)
   → identité "Apple Development", réutilisée entre les builds.
NOTE
else
  cat <<'NOTE'
   Signature stable (Apple Development) : les autorisations TCC persistent entre
   les builds. Première fois après ce changement d'identité : re-accordez
   l'Accessibilité une dernière fois (le cdhash a changé une fois).
NOTE
fi

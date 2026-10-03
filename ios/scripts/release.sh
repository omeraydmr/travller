#!/bin/zsh
# Stubly'yi Release (production sunucusu) olarak derler, kayıtlı cihazlara kurulabilir IPA çıkarır
# ve istenirse bağlı iPhone'a kurar.
#   scripts/release.sh            → ios/dist/Stubly.ipa
#   scripts/release.sh --install  → ayrıca bağlı ilk fiziksel iPhone'a kurar ve açar
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHIVE=build/Stubly.xcarchive
DIST=dist

xcodegen generate >/dev/null
rm -rf "$ARCHIVE" "$DIST"
xcodebuild -project Stubly.xcodeproj -scheme Stubly -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath build/DerivedData \
  -allowProvisioningUpdates archive | grep -E "error:|ARCHIVE" || true
[ -d "$ARCHIVE" ] || { echo "Arşiv oluşmadı"; exit 1; }

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$DIST" \
  -exportOptionsPlist Config/ExportOptions.plist -allowProvisioningUpdates | grep -E "error|EXPORT" || true
[ -f "$DIST/Stubly.ipa" ] || { echo "IPA oluşmadı"; exit 1; }
echo "IPA: $PWD/$DIST/Stubly.ipa"

if [[ "${1:-}" == "--install" ]]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null | grep physical | grep iPhone | grep available | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)
  [ -n "$DEVICE" ] || { echo "Bağlı iPhone bulunamadı"; exit 1; }
  xcrun devicectl device install app --device "$DEVICE" "$DIST/Stubly.ipa" >/dev/null
  xcrun devicectl device process launch --device "$DEVICE" com.omeraydemir.stubly >/dev/null
  echo "Kuruldu ve açıldı: $DEVICE"
fi

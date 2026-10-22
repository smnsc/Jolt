#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h:h}"
app_path="${project_dir}/build/Jolt.app"
dmg_path="${project_dir}/build/Jolt.dmg"

if [[ ! -d "${app_path}" ]]; then
  print -u2 "Build the app first with scripts/macos/build-app.sh."
  exit 2
fi

staging_path="$(mktemp -d "${project_dir}/build/dmg-stage.XXXXXX")"
mount_path="${staging_path}/mounted"
mounted=false
cleanup() {
  if [[ "${mounted}" == true ]]; then
    hdiutil detach "${mount_path}" -quiet || return
  fi
  rm -rf "${staging_path}"
}
trap cleanup EXIT
mkdir -p "${staging_path}/contents/.background"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
CLANG_MODULE_CACHE_PATH="${project_dir}/build/dmg-module-cache" \
  swift "${script_dir}/generate-dmg-background.swift" "${staging_path}/contents/.background/install.tiff"
contents_path="${staging_path}/contents"
ditto "${app_path}" "${contents_path}/Jolt.app"
ln -s /Applications "${contents_path}/Applications"
hdiutil create -volname "Jolt" -srcfolder "${contents_path}" -format UDRW "${staging_path}/writable.dmg"
hdiutil attach "${staging_path}/writable.dmg" -mountpoint "${mount_path}" -nobrowse -quiet
mounted=true
osascript "${script_dir}/configure-dmg.applescript" "${mount_path}"
[[ -s "${mount_path}/.DS_Store" ]] || { print -u2 "Finder did not save the DMG layout."; exit 1; }
hdiutil detach "${mount_path}" -quiet
mounted=false
hdiutil convert "${staging_path}/writable.dmg" -format UDZO -o "${dmg_path}" -ov

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  xcrun notarytool submit "${dmg_path}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_PASSWORD}" \
    --wait
  xcrun stapler staple "${dmg_path}"
fi

print "Packaged ${dmg_path}"

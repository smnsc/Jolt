#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
app_path="${project_dir}/build/Jolt.app"
dmg_path="${project_dir}/build/Jolt.dmg"

if [[ ! -d "${app_path}" ]]; then
  print -u2 "Build the app first with scripts/build-app.sh."
  exit 2
fi

rm -f "${dmg_path}"
hdiutil create -volname "Jolt" -srcfolder "${app_path}" -ov -format UDZO "${dmg_path}"

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  xcrun notarytool submit "${dmg_path}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_PASSWORD}" \
    --wait
  xcrun stapler staple "${dmg_path}"
fi

print "Packaged ${dmg_path}"

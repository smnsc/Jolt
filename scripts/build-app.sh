#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
configuration="${CONFIGURATION:-release}"
output_dir="${project_dir}/build"
app_dir="${output_dir}/Jolt.app"
contents_dir="${app_dir}/Contents"
plist_path="${contents_dir}/Info.plist"
asset_info_path="${output_dir}/AppIconInfo.plist"
scratch_path="${output_dir}/SwiftPM"
module_cache_path="${output_dir}/ModuleCache"
build_number_path="${output_dir}/.build-number"

# Keep the release version in the bundle template; builds may override it.
marketing_version="${MARKETING_VERSION-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${project_dir}/Resources/Info.plist")}"
release_version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
if [[ ! "${marketing_version}" =~ ${release_version_pattern} ]]; then
  print -u2 "MARKETING_VERSION must be MAJOR.MINOR.PATCH with no leading zeros (for example, 0.1.0)."
  exit 2
fi

last_build_number=0
if [[ -r "${build_number_path}" ]]; then
  stored_build_number="$(<"${build_number_path}")"
  if [[ "${stored_build_number}" == <-> ]]; then
    last_build_number="${stored_build_number}"
  fi
fi

# Recover the counter from the current app if the state file was removed while
# leaving the built product in place.
if [[ -f "${plist_path}" ]]; then
  bundled_build_number="$(
    /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${plist_path}" 2>/dev/null || true
  )"
  if [[ "${bundled_build_number}" == <-> ]] && (( bundled_build_number > last_build_number )); then
    last_build_number="${bundled_build_number}"
  fi
fi

if [[ -n "${BUILD_NUMBER:-}" ]]; then
  build_number_pattern='^[1-9][0-9]*$'
  if [[ ! "${BUILD_NUMBER}" =~ ${build_number_pattern} ]]; then
    print -u2 "BUILD_NUMBER must be a positive integer."
    exit 2
  fi
  build_number="${BUILD_NUMBER}"
else
  # Match the release workflow's timestamp scale so a newer local build is
  # not mistaken for an older build by Sparkle. Still advance for rapid builds
  # or when the clock moves backwards.
  build_number="$(date +%s)"
  if (( build_number <= last_build_number )); then
    build_number="$(( last_build_number + 1 ))"
  fi
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

cd "${project_dir}"
mkdir -p "${scratch_path}" "${module_cache_path}"
export SWIFTPM_MODULECACHE_OVERRIDE="${module_cache_path}"
export CLANG_MODULE_CACHE_PATH="${module_cache_path}"
swift "${script_dir}/generate-app-icon.swift" \
  "${project_dir}/Resources/AppIcon.png" \
  "${project_dir}/Resources/Assets.xcassets/AppIcon.appiconset"
swift build --disable-sandbox --scratch-path "${scratch_path}" \
  -c "${configuration}" --arch arm64 --arch x86_64
binary_dir="$(swift build --disable-sandbox --scratch-path "${scratch_path}" \
  -c "${configuration}" --arch arm64 --arch x86_64 --show-bin-path)"

mkdir -p "${contents_dir}/MacOS" "${contents_dir}/Resources" "${contents_dir}/Frameworks"
# SPM links the framework but this custom .app packager must embed it itself.
sparkle_framework="${scratch_path}/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "${sparkle_framework}" ]]; then
  print -u2 "Sparkle framework not found at ${sparkle_framework}."
  exit 2
fi
rm -rf "${contents_dir}/Frameworks/Sparkle.framework"
ditto "${sparkle_framework}" "${contents_dir}/Frameworks/Sparkle.framework"
cp "${project_dir}/LICENSE" "${contents_dir}/Resources/LICENSE.txt"
cp "${project_dir}/THIRD_PARTY_NOTICES.md" "${contents_dir}/Resources/THIRD_PARTY_NOTICES.txt"
cp "${binary_dir}/Jolt" "${contents_dir}/MacOS/Jolt"
cp "${project_dir}/Resources/Info.plist" "${plist_path}"

# Compile the layered icon alongside the catalog's legacy fallback and menu icon.
xcrun actool "${project_dir}/Resources/Assets.xcassets" \
  "${project_dir}/Resources/AppIcon.icon" \
  --compile "${contents_dir}/Resources" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "${asset_info_path}" \
  --target-device mac \
  --development-region en >/dev/null

/usr/libexec/PlistBuddy -c "Merge ${asset_info_path}" "${plist_path}"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_IDENTIFIER:-co.simonsc.jolt}" "${plist_path}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${marketing_version}" "${plist_path}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${build_number}" "${plist_path}"

# Render concrete identifiers: codesign does not expand Xcode build variables.
entitlements_path="${output_dir}/Jolt.entitlements"
sed "s/co.simonsc.jolt/${BUNDLE_IDENTIFIER:-co.simonsc.jolt}/g" \
  "${project_dir}/Resources/Jolt.entitlements" > "${entitlements_path}"
if [[ -n "${UPDATE_FEED_URL:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL ${UPDATE_FEED_URL}" "${plist_path}"
fi

# Sign nested code from the inside out. Never propagate the host's sandbox
# entitlements to Sparkle's installer with codesign --deep.
signing_args=(--force --sign "${SIGNING_IDENTITY:--}")
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  signing_args+=(--options runtime --timestamp)
fi
framework="${contents_dir}/Frameworks/Sparkle.framework/Versions/B"
codesign "${signing_args[@]}" "${framework}/XPCServices/Installer.xpc"
codesign "${signing_args[@]}" --preserve-metadata=entitlements "${framework}/XPCServices/Downloader.xpc"
codesign "${signing_args[@]}" "${framework}/Autoupdate"
codesign "${signing_args[@]}" "${framework}/Updater.app"
codesign "${signing_args[@]}" "${contents_dir}/Frameworks/Sparkle.framework"
# Ad-hoc signatures retain their default hash-bound requirement. Do not weaken
# Keychain access to an identifier-only requirement to preserve login on updates.
codesign "${signing_args[@]}" --entitlements "${entitlements_path}" \
  --identifier "${BUNDLE_IDENTIFIER:-co.simonsc.jolt}" "${app_dir}"
codesign --verify --deep --strict --verbose=2 "${app_dir}"

if (( build_number > last_build_number )); then
  print -r -- "${build_number}" > "${build_number_path}"
fi

print "Built ${app_dir} — ${marketing_version}+build.${build_number} (Jolt build ${build_number})"

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
  if [[ "${BUILD_NUMBER}" != <-> ]] || (( BUILD_NUMBER < 1 )); then
    print -u2 "BUILD_NUMBER must be a positive integer."
    exit 2
  fi
  build_number="${BUILD_NUMBER}"
else
  build_number="$(( last_build_number + 1 ))"
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

mkdir -p "${contents_dir}/MacOS" "${contents_dir}/Resources"
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

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_IDENTIFIER:-com.local.Jolt}" "${plist_path}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${MARKETING_VERSION:-0.1.0}" "${plist_path}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${build_number}" "${plist_path}"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp \
    --entitlements "${project_dir}/Resources/Jolt.entitlements" \
    --sign "${SIGNING_IDENTITY}" "${app_dir}"
  codesign --verify --deep --strict --verbose=2 "${app_dir}"
else
  # Seal local builds too, so they are not treated as unsigned applications.
  # The default ad-hoc requirement includes the build's code hash; unlike an
  # identifier-only requirement, another local app cannot impersonate it.
  codesign --force --deep \
    --entitlements "${project_dir}/Resources/Jolt.entitlements" \
    --identifier "${BUNDLE_IDENTIFIER:-com.local.Jolt}" \
    --sign - "${app_dir}"
  codesign --verify --deep --strict --verbose=2 "${app_dir}"
fi

if (( build_number > last_build_number )); then
  print -r -- "${build_number}" > "${build_number_path}"
fi

print "Built ${app_dir} (version ${MARKETING_VERSION:-0.1.0}, build ${build_number})"

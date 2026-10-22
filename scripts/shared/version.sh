# Shared by Bash and Zsh callers running from any directory.
# The caller sets project_dir before sourcing this file.
jolt_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${project_dir}/Resources/Info.plist")
jolt_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${project_dir}/Resources/Info.plist")
jolt_version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
jolt_build_pattern='^[1-9][0-9]*$'
if [[ ! "$jolt_version" =~ $jolt_version_pattern || ! "$jolt_build" =~ $jolt_build_pattern ]]; then
  echo 'Resources/Info.plist must contain a MAJOR.MINOR.PATCH version and positive integer build number without leading zeros.' >&2
  exit 2
fi
if [[ "${MARKETING_VERSION-$jolt_version}" != "$jolt_version" || "${BUILD_NUMBER-$jolt_build}" != "$jolt_build" ]]; then
  echo 'Version overrides must match Resources/Info.plist. Edit and commit that file to change version or build number.' >&2
  exit 2
fi

#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

cd "${project_dir}"
module_cache_path="${project_dir}/build/TestModuleCache"
mkdir -p "${module_cache_path}"
export SWIFTPM_MODULECACHE_OVERRIDE="${module_cache_path}"
export CLANG_MODULE_CACHE_PATH="${module_cache_path}"
swift test --disable-sandbox --scratch-path "${project_dir}/build/TestSwiftPM" "$@"

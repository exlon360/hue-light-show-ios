#!/usr/bin/env bash
set -euo pipefail

PROJECT="HueLightShow.xcodeproj"
SCHEME="HueLightShow"
CONFIGURATION="Release"
BUILD_ROOT="build/hue-light-show-unsigned-ipa"
APP_PATH="${BUILD_ROOT}/Build/Products/${CONFIGURATION}-iphoneos/HueLightShow.app"
PAYLOAD_DIR="${BUILD_ROOT}/Payload"
IPA_PATH="${BUILD_ROOT}/HueLightShow-unsigned.ipa"

rm -rf "${BUILD_ROOT}"
mkdir -p "${BUILD_ROOT}"

LOG_PATH="${BUILD_ROOT}/xcodebuild.log"

set +e
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -sdk iphoneos \
  -derivedDataPath "${BUILD_ROOT}/DerivedData" \
  SYMROOT="${BUILD_ROOT}/Build/Products" \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tee "${LOG_PATH}"
STATUS=${PIPESTATUS[0]}
set -e

if [[ "${STATUS}" -ne 0 ]]; then
  echo "::group::xcodebuild diagnostics"
  grep -Ei "error:|fatal error:|BUILD FAILED|Check dependencies" "${LOG_PATH}" | tail -80 || true
  echo "::endgroup::"

  while IFS= read -r line; do
    escaped="${line//'%'/'%25'}"
    escaped="${escaped//$'\r'/'%0D'}"
    escaped="${escaped//$'\n'/'%0A'}"
    echo "::error title=Xcode build::${escaped}"
  done < <(grep -Ei "error:|fatal error:|BUILD FAILED|Check dependencies" "${LOG_PATH}" | tail -20 || true)

  exit "${STATUS}"
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Expected app bundle was not created: ${APP_PATH}" >&2
  exit 1
fi

mkdir -p "${PAYLOAD_DIR}"
cp -R "${APP_PATH}" "${PAYLOAD_DIR}/"

(
  cd "${BUILD_ROOT}"
  /usr/bin/zip -qry "HueLightShow-unsigned.ipa" "Payload"
)

echo "${IPA_PATH}"

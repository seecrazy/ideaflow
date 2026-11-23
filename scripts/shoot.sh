#!/bin/zsh
# 全页面截图:亮色 6 页 + 深色 3 页(需先 build)
set -e
APP=$(find ~/Library/Developer/Xcode/DerivedData/IdeaFlow-*/Build/Products/Debug-iphonesimulator -maxdepth 1 -name IdeaFlow.app | head -1)
OUT=docs/screenshots
mkdir -p "$OUT"

xcrun simctl uninstall booted com.ideaflow.app 2>/dev/null || true
xcrun simctl install booted "$APP"

shoot() {
  local name=$1; shift
  xcrun simctl terminate booted com.ideaflow.app 2>/dev/null || true
  sleep 1
  xcrun simctl launch booted com.ideaflow.app -seedDemo "$@" >/dev/null
  sleep 4
  xcrun simctl io booted screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "shot $name"
}

xcrun simctl ui booted appearance light
shoot 01-home
shoot 02-detail -openDetail
shoot 03-search -openPageSearch
shoot 04-tags -openPageTags
shoot 05-settings -openPageSettings
shoot 06-recycle -openRecycle

xcrun simctl ui booted appearance dark
shoot 07-home-dark
shoot 08-detail-dark -openDetail
shoot 09-search-dark -openPageSearch

xcrun simctl ui booted appearance light
# 压缩为 jpg 供审查
for f in "$OUT"/*.png; do
  sips -s format jpeg -s formatOptions 82 -Z 820 "$f" --out "${f:r}.jpg" >/dev/null 2>&1
done
echo done

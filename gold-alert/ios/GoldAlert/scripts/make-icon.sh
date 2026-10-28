#!/usr/bin/env bash
# 手动还原图标：把 Icon.png.b64 解码成 Icon.png。
# pack-onsite.sh 打包时会自动做这一步；直接用 xtool dev 编译前先跑一次本脚本。
if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - <<'PY'
import base64
data = base64.b64decode(open("Icon.png.b64", encoding="utf-8").read())
open("Icon.png", "wb").write(data)
print(f"图标已还原 Icon.png（{len(data)} 字节）")
PY

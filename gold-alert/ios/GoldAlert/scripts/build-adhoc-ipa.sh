#!/usr/bin/env bash
# 只出 Ad Hoc IPA（写入 D:\ota-site，安装合并进 index.html）。
if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi
export DO_PULL="${DO_PULL:-1}"
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pack-onsite.sh"

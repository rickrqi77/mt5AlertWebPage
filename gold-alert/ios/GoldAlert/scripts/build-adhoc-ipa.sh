#!/usr/bin/env bash
# 只出 Ad Hoc IPA（写入 D:\ota-site，刷新与其它 App 相同的 index）。
if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi
export DO_PULL="${DO_PULL:-1}"
# 必须经 bash 调用：经 GitHub API 推送的 .sh 会丢失可执行权限位（644），
# 直跑会 Permission denied（exit 126，2026-10-29 图标那次实际踩中）。
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pack-onsite.sh" "$@"

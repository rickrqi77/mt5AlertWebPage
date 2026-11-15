#!/usr/bin/env bash
# 把 GitHub Actions 编好的未签名手表端 .app 嵌入 IPA：
# 解压 → Payload/<App>.app/Watch/GoldAlertWatch.app → 重新打包。
# 只处理未签名 IPA；签名仍由 pack-onsite.sh 的 zsign 一步完成
# （zsign 支持多个 -m 描述文件，按 App ID 给手机/手表/复杂功能各配一份）。
if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi
set -euo pipefail

in_ipa="${1:?用法：embed-watch-app.sh <未签名IPA> <手表.app> <输出IPA>}"
watch_app="${2:?缺少手表 .app 路径}"
out_ipa="${3:?缺少输出 IPA 路径}"

[[ -f "$in_ipa" ]] || { echo "找不到 IPA：$in_ipa" >&2; exit 1; }
[[ -d "$watch_app" ]] || { echo "找不到手表 App：$watch_app" >&2; exit 1; }

out_dir="$(mkdir -p "$(dirname "$out_ipa")" && cd "$(dirname "$out_ipa")" && pwd)"
out_ipa="$out_dir/$(basename "$out_ipa")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

unzip -q "$in_ipa" -d "$work"
app_path="$(find "$work/Payload" -maxdepth 1 -name '*.app' -type d | head -1)"
[[ -n "$app_path" ]] || { echo "IPA 里找不到 .app" >&2; exit 1; }

mkdir -p "$app_path/Watch"
dest="$app_path/Watch/$(basename "$watch_app")"
rm -rf "$dest"
cp -R "$watch_app" "$dest"
# 手表 .app 若带了编译机上的签名残留，去掉，zsign 会统一重签。
rm -rf "$dest/_CodeSignature"

rm -f "$out_ipa"
(cd "$work" && zip -qry "$out_ipa" Payload)
echo "已嵌入手表端：$out_ipa"

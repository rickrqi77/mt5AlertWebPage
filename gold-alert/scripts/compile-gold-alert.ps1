$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Read-TextFile([string]$path) {
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) {
        return [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2).Trim()
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        return [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3).Trim()
    }
    return [Text.Encoding]::UTF8.GetString($bytes).Trim()
}

$src = Join-Path $env:TEMP 'GoldPriceAlert.mq5'
Write-Output '正在下载最新 GoldPriceAlert.mq5 ...'
Invoke-WebRequest -Uri 'https://alertdata.pages.dev/GoldPriceAlert.mq5' -OutFile $src -UseBasicParsing
$versionLine = Select-String -Path $src -Pattern '#property version' | Select-Object -First 1
if ($versionLine) { Write-Output $versionLine.Line.Trim() }

$root = Join-Path $env:APPDATA 'MetaQuotes\Terminal'
if (-not (Test-Path -LiteralPath $root)) {
    Write-Output '没有找到 MT5 数据目录。请先在这台电脑上打开一次 MetaTrader 5。'
    exit 1
}

$started = Get-Date
$ok = 0
Get-ChildItem -LiteralPath $root -Directory | ForEach-Object {
    if ($_.Name -eq 'Common') { return }
    $originFile = Join-Path $_.FullName 'origin.txt'
    $experts = Join-Path $_.FullName 'MQL5\Experts'
    if (-not (Test-Path -LiteralPath $originFile)) { return }
    if (-not (Test-Path -LiteralPath $experts)) { return }

    $origin = (Read-TextFile $originFile).Trim('"').Trim()
    $editor = Join-Path $origin 'metaeditor64.exe'
    if (-not (Test-Path -LiteralPath $editor)) {
        $editor = Join-Path $origin 'metaeditor.exe'
    }
    if (-not (Test-Path -LiteralPath $editor)) {
        Write-Output "跳过：找不到 MetaEditor ($origin)"
        return
    }

    $dest = Join-Path $experts 'GoldPriceAlert.mq5'
    $ex5 = Join-Path $experts 'GoldPriceAlert.ex5'
    $log = Join-Path $experts 'GoldPriceAlert.log'
    Copy-Item -LiteralPath $src -Destination $dest -Force
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }

    Write-Output "正在编译: $dest"
    $proc = Start-Process -FilePath $editor -ArgumentList @("/compile:$dest", "/log:$log") -Wait -PassThru -WindowStyle Hidden
    $fresh = $false
    if (Test-Path -LiteralPath $ex5) {
        $fresh = (Get-Item -LiteralPath $ex5).LastWriteTime -ge $started.AddSeconds(-5)
    }
    if ($fresh) {
        $script:ok = $script:ok + 1
        Write-Output "已覆盖: $ex5"
    } else {
        Write-Output "编译失败: $dest"
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 30 }
    }
}

if ($ok -lt 1) {
    Write-Output '没有编译成功。请确认 MT5 已安装，并且这台电脑上打开过一次。'
    exit 1
}
Write-Output '完成。图表上正在运行的 EA 通常会自动重新加载。Experts 里应出现新的 EA initialized 版本。'
exit 0

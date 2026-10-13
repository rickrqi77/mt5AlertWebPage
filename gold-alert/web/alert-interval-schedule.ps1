param(
    [switch]$Query,
    [switch]$Install,
    [string]$Bat
)

$ErrorActionPreference = 'Stop'

# 改钟点只改这三行，然后重新双击 install-alert-interval-tasks.bat。
$DayStart = 8
$EveningStart = 18
$SleepStart = 23

function Get-Interval {
    $now = Get-Date
    $hour = $now.Hour
    $dow = [int]$now.DayOfWeek
    if ($hour -ge $SleepStart -or $hour -lt $DayStart) {
        return @{ Sec = 3600; Tag = 'sleep' }
    }
    if ($dow -ge 1 -and $dow -le 5 -and $hour -lt $EveningStart) {
        return @{ Sec = 3; Tag = 'day' }
    }
    if ($dow -ge 1 -and $dow -le 5) {
        return @{ Sec = 10; Tag = 'evening' }
    }
    return @{ Sec = 3600; Tag = 'weekend' }
}

if ($Query) {
    $picked = Get-Interval
    Write-Output ("{0} {1}" -f $picked.Sec, $picked.Tag)
    exit 0
}

if (-not $Install) {
    Write-Error 'Use -Query or -Install'
    exit 1
}

if (-not $Bat -or -not (Test-Path -LiteralPath $Bat)) {
    Write-Error "找不到 set-alert-interval.bat: $Bat"
    exit 1
}

$batPath = (Resolve-Path -LiteralPath $Bat).Path
$action = New-ScheduledTaskAction -Execute $batPath -Argument 'auto'
$day = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At ('{0:D2}:00' -f $DayStart)
$evening = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At ('{0:D2}:00' -f $EveningStart)
$sleep = New-ScheduledTaskTrigger -Daily -At ('{0:D2}:00' -f $SleepStart)
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$logon = New-ScheduledTaskTrigger -AtLogOn -User $me
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Limited
$desc = "工作日 ${DayStart}:00-${EveningStart}:00 为 3 秒，工作日 ${EveningStart}:00-${SleepStart}:00 为 10 秒，其余时间为 3600 秒。按当时钟点写入。"
Register-ScheduledTask -TaskName 'GoldAlert Interval' -Action $action -Trigger $day,$evening,$sleep,$logon -Settings $settings -Principal $principal -Description $desc -Force | Out-Null
Write-Output '已创建计划任务：GoldAlert Interval'
& cmd.exe /c "`"$batPath`" auto"
exit $LASTEXITCODE

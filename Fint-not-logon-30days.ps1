Import-Module ActiveDirectory -ErrorAction Stop

# Параметры
$DaysInactive = 30
$TimeThreshold = (Get-Date).AddDays(-$DaysInactive)
$BlockedPCOU = "OU=BlockedPC,OU=Blocked,DC=storm,DC=local"

# Получаем все компьютеры с lastLogonTimestamp и Enabled
$Computers = Get-ADComputer -Filter { lastLogonTimestamp -lt $TimeThreshold -and Enabled -eq $true } -Properties lastLogonTimestamp, DistinguishedName

# Фильтруем: исключаем те, что находятся в BlockedPC OU или её подразделениях
$FilteredComputers = $Computers | Where-Object {
    $_.DistinguishedName -notlike "*,$BlockedPCOU"
}

# Подготавливаем вывод
$Result = $FilteredComputers | Select-Object Name,
    @{Name = "LastLogon"; Expression = { [DateTime]::FromFileTime($_.lastLogonTimestamp) }},
    DistinguishedName

# Экспорт в CSV (опционально)
$Result | Export-Csv -Path "C:\temp\InactiveComputers_NotInBlockedPC.csv" -NoTypeInformation -Encoding UTF8

# Вывод в консоль (можно закомментировать при массовом использовании)
$Result | Format-Table -AutoSize
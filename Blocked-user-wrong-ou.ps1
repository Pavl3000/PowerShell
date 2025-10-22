# Получаем DistinguishedName целевой OU
$blockedUsersOU = "OU=Blocked,DC=storm,DC=local"

# Получаем всех отключённых пользователей
$disabledUsers = Get-ADUser -Filter {Enabled -eq $false} -Properties DistinguishedName

# Фильтруем тех, кто НЕ находится в Blocked OU или её подразделениях
$disabledUsersOutside = $disabledUsers | Where-Object {
    $_.DistinguishedName -notlike "*,$blockedUsersOU"
}

# $disabledUsersOutside | Select-Object Name, SamAccountName, DistinguishedName

cls
$disabledUsersOutside | Select-Object Name, SamAccountName, DistinguishedName | ft -Wrap

$exportPath = "C:\Temp\DisabledUsersOutsideBlockedOU.csv"
$disabledUsersOutside | Select-Object Name, SamAccountName, DistinguishedName |
    Export-Csv -Path $exportPath -Encoding UTF8 -NoTypeInformation
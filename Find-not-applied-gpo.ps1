# Убедитесь, что модули загружены
Import-Module GroupPolicy
Import-Module ActiveDirectory

# Получаем все OU
$OUs = Get-ADOrganizationalUnit -Filter * -Properties Name, DistinguishedName

# Собираем результаты
$DisabledLinks = foreach ($OU in $OUs) {
    $links = Get-GPInheritance -Target $OU.DistinguishedName -ErrorAction SilentlyContinue
    foreach ($link in $links.GpoLinks) {
        if (-not $link.Enabled) {
            [PSCustomObject]@{
                OUName        = $OU.Name
                OUDN          = $OU.DistinguishedName
                GPOName       = $link.DisplayName
                GPOID         = $link.GpoId
                LinkEnabled   = $link.Enabled
            }
        }
    }
}

# Выводим результат
$DisabledLinks | Format-Table -AutoSize

# При необходимости — экспорт в CSV
$DisabledLinks | Export-Csv -Path "C:\Temp\DisabledGpoLinks.csv" -NoTypeInformation -Encoding UTF8
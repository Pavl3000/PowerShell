# Убедитесь, что модуль GroupPolicy загружен
Import-Module GroupPolicy

# Получаем все GPO в домене
$AllGPOs = Get-GPO -All | Select-Object DisplayName, ID

# Получаем все привязки GPO (включая OU, домены и сайты)
$LinkedGPOIds = @()
$Domains = (Get-ADDomain).DistinguishedName
$LinkedGPOIds += Get-GPInheritance -Target $Domains | Select-Object -ExpandProperty GpoLinks | Select-Object -ExpandProperty GpoId

# Получаем все OU и проверяем их привязки
$OUs = Get-ADOrganizationalUnit -Filter * -Properties gPLink
foreach ($OU in $OUs) {
    if ($OU.gPLink) {
        # Извлекаем GUID из gPLink (формат: [LDAP://CN={GUID},...;0])
        $gPLinks = $OU.gPLink -split ']\[' | ForEach-Object {
            if ($_ -match '\{([0-9a-fA-F\-]+)\}') {
                $matches[1]
            }
        }
        $LinkedGPOIds += $gPLinks
    }
}

# Убираем дубликаты
$LinkedGPOIds = $LinkedGPOIds | Sort-Object -Unique

# Находим GPO без привязок
$UnlinkedGPOs = $AllGPOs | Where-Object { $_.ID -notin $LinkedGPOIds }

# Выводим результат
$UnlinkedGPOs | Format-Table DisplayName
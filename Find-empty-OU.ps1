Import-Module ActiveDirectory -ErrorAction Stop

# Получаем все OU в домене
$allOUs = Get-ADOrganizationalUnit -Filter * -Properties DistinguishedName

$trulyEmptyOUs = foreach ($ou in $allOUs) {
    # Ищем ЛЮБОЙ дочерний объект (включая другие OU) на первом уровне
    $anyChild = Get-ADObject -SearchBase $ou.DistinguishedName -SearchScope OneLevel -Filter * -ResultSetSize 1

    # Если дочерних объектов нет — OU полностью пуста
    if (-not $anyChild) {
        [PSCustomObject]@{
            Name             = $ou.Name
            DistinguishedName = $ou.DistinguishedName
        }
    }
}

$trulyEmptyOUs | ft -Wrap

# Экспорт в CSV
 $outputFile = "TrulyEmptyOUs_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
 $trulyEmptyOUs | Export-Csv -Path "C:\Temp\$outputFile" -NoTypeInformation -Encoding UTF8

Write-Host "Найдено $($trulyEmptyOUs.Count) полностью пустых OU (без каких-либо дочерних объектов)." -ForegroundColor Green
Write-Host "Результат сохранён в: $outputFile"
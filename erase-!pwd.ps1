# Путь к OU
$targetOU = "OU=Oustside ORG,DC=storm,DC=local"

# Шаблон для поиска пароля в описании (буквы + цифры + восклицательный знак в конце)
$PasswordPattern = '^[a-zA-Z0-9]+!$'

# Получаем всех пользователей в OU и подразделениях
$users = Get-ADUser -SearchBase $targetOU -Filter * -Properties Description,DistinguishedName,SamAccountName,Name

$results = @()

foreach ($user in $users) {
    $desc = $user.Description
    if ($desc) {
        # Разбиваем описание на строки (на случай, если там несколько строк)
        $lines = $desc -split "`r`n" | Where-Object { $_ -match '\S' }  # убираем пустые строки

        $newLines = @()
        $foundPassword = $false
        $extractedPassword = $null

        foreach ($line in $lines) {
            if ($line -match $PasswordPattern) {
                # Это пароль — запоминаем и не добавляем в новое описание
                $extractedPassword = $line
                $foundPassword = $true
            } else {
                # Это не пароль — оставляем
                $newLines += $line
            }
        }

        if ($foundPassword) {
            # Сохраняем информацию в результат
            $results += [PSCustomObject]@{
                Name             = $user.Name
                SamAccountName   = $user.SamAccountName
                DistinguishedName = $user.DistinguishedName
                Password         = $extractedPassword
                OriginalDescription = $desc
            }

            # Формируем новое описание без пароля
            $newDescription = ($newLines -join "`r`n").Trim()
            if ([string]::IsNullOrWhiteSpace($newDescription)) {
                $newDescription = $null
            }

            # Обновляем описание в AD
            Set-ADUser -Identity $user.DistinguishedName -Description $newDescription
            Write-Host "Обновлён пользователь: $($user.SamAccountName)"
        }
    }
}

# Экспорт в CSV
$outputFile = "C:\Temp\ExtractedPasswords_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "Найдено и удалено $($results.Count) паролей. Результат сохранён в: $outputFile"
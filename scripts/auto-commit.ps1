# Auto-commit script
# Автоматически создает коммит с правильным форматом

param(
    [string]$Message = "",
    [string]$Type = ""
)

# Цвета для вывода
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-ColorOutput Green "=== Автоматический коммит ==="

# Проверка, что мы в git репозитории
if (-not (Test-Path .git)) {
    Write-ColorOutput Red "ОШИБКА: Не найден .git. Запустите скрипт из корня репозитория."
    exit 1
}

# Проверка статуса
$status = git status --porcelain
if ([string]::IsNullOrWhiteSpace($status)) {
    Write-ColorOutput Yellow "Нет изменений для коммита."
    exit 0
}

Write-ColorOutput Cyan "`nИзмененные файлы:"
git status --short

# Проверка артефактов
$changelogUpdated = $false
$worklogUpdated = $false

$staged = git diff --cached --name-only
$unstaged = git diff --name-only

$allFiles = ($staged + $unstaged) | Where-Object { $_ -ne $null }

# Проверяем, есть ли изменения в коде (требуют артефакты)
$codeChanged = $false
foreach ($file in $allFiles) {
    if ($file -match '^(lib/|android/|assets/|test/|pubspec\.yaml|pubspec\.lock|analysis_options\.yaml)') {
        $codeChanged = $true
        break
    }
}

if ($codeChanged) {
    Write-ColorOutput Cyan "`nПроверка артефактов..."
    
    # Проверяем CHANGELOG.md
    $changelogInChanges = $allFiles | Where-Object { $_ -eq "CHANGELOG.md" }
    if ($changelogInChanges) {
        $changelogContent = Get-Content "CHANGELOG.md" -Raw -ErrorAction SilentlyContinue
        if ($changelogContent -match '## \[Unreleased\]') {
            $changelogUpdated = $true
            Write-ColorOutput Green "  ✓ CHANGELOG.md обновлен"
        } else {
            Write-ColorOutput Red "  ✗ CHANGELOG.md не содержит секцию [Unreleased]"
        }
    } else {
        Write-ColorOutput Red "  ✗ CHANGELOG.md не в изменениях"
    }
    
    # Проверяем AI_WORKLOG.md
    $worklogInChanges = $allFiles | Where-Object { $_ -eq "AI_WORKLOG.md" }
    if ($worklogInChanges) {
        $worklogContent = Get-Content "AI_WORKLOG.md" -Raw -ErrorAction SilentlyContinue
        $today = Get-Date -Format "yyyy-MM-dd"
        if ($worklogContent -match $today) {
            $worklogUpdated = $true
            Write-ColorOutput Green "  ✓ AI_WORKLOG.md содержит запись за сегодня"
        } else {
            Write-ColorOutput Yellow "  ⚠ AI_WORKLOG.md не содержит запись за сегодня ($today)"
        }
    } else {
        Write-ColorOutput Red "  ✗ AI_WORKLOG.md не в изменениях"
    }
    
    if (-not $changelogUpdated -or -not $worklogUpdated) {
        Write-ColorOutput Red "`nОШИБКА: Не все артефакты обновлены!"
        Write-ColorOutput Yellow "Используйте Cursor команды:"
        Write-ColorOutput Yellow "  - update-artifacts (обновить все)"
        Write-ColorOutput Yellow "  - update-changelog (только CHANGELOG)"
        Write-ColorOutput Yellow "  - log-work (только AI_WORKLOG)"
        exit 1
    }
}

# Определение типа коммита
if ([string]::IsNullOrWhiteSpace($Type)) {
    Write-ColorOutput Cyan "`nАнализ изменений для определения типа коммита..."
    
    $hasLib = $allFiles | Where-Object { $_ -match '^lib/' }
    $hasAndroid = $allFiles | Where-Object { $_ -match '^android/' }
    $hasDocs = $allFiles | Where-Object { $_ -match '^docs/' -or $_ -match '\.md$' }
    $hasTest = $allFiles | Where-Object { $_ -match '^test/' }
    $hasChangelog = $allFiles | Where-Object { $_ -eq "CHANGELOG.md" }
    $hasWorklog = $allFiles | Where-Object { $_ -eq "AI_WORKLOG.md" }
    
    if ($hasLib -or $hasAndroid) {
        # Смотрим на diff для определения feat/fix
        $diff = git diff HEAD --stat
        if ($diff -match 'fix|bug|error|исправ|баг') {
            $Type = "fix"
        } elseif ($hasTest) {
            $Type = "test"
        } else {
            $Type = "feat"
        }
    } elseif ($hasDocs -or $hasChangelog -or $hasWorklog) {
        $Type = "docs"
    } else {
        $Type = "chore"
    }
    
    Write-ColorOutput Green "  Определен тип: $Type"
}

# Запрос сообщения коммита
if ([string]::IsNullOrWhiteSpace($Message)) {
    Write-ColorOutput Cyan "`nВведите описание коммита (без префикса типа):"
    $Message = Read-Host
}

if ([string]::IsNullOrWhiteSpace($Message)) {
    Write-ColorOutput Red "ОШИБКА: Сообщение коммита не может быть пустым."
    exit 1
}

# Формирование полного сообщения
$commitMessage = "$Type(client): $Message"

Write-ColorOutput Cyan "`nСообщение коммита:"
Write-ColorOutput Yellow "  $commitMessage"

# Подтверждение
Write-ColorOutput Cyan "`nСоздать коммит? (Y/n)"
$confirm = Read-Host
if ($confirm -eq "n" -or $confirm -eq "N") {
    Write-ColorOutput Yellow "Отменено."
    exit 0
}

# Добавление всех изменений
Write-ColorOutput Cyan "`nДобавление файлов..."
git add .

# Создание коммита
Write-ColorOutput Cyan "Создание коммита..."
git commit -m $commitMessage

if ($LASTEXITCODE -eq 0) {
    Write-ColorOutput Green "`n✓ Коммит создан успешно!"
    Write-ColorOutput Cyan "`nТекущий статус:"
    git status --short
} else {
    Write-ColorOutput Red "`n✗ Ошибка при создании коммита."
    exit 1
}


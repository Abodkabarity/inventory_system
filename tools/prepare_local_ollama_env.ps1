[CmdletBinding()]
param(
    [string]$SupabaseUrl,
    [string]$SupabaseAnonKey,
    [string]$OllamaUrl = 'http://127.0.0.1:11434',
    [int]$FlutterPort = 54882,
    [string]$Model
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

function Get-DotEnvValue([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $line = Get-Content -LiteralPath $Path | Where-Object {
        $_ -match "^\\s*$([regex]::Escape($Name))\\s*="
    } | Select-Object -First 1
    if (-not $line) { return $null }
    $value = ($line -split '=', 2)[1].Trim()
    return $value.Trim('"').Trim("'")
}

if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
    $SupabaseUrl = Get-DotEnvValue (Join-Path $projectRoot '.env') 'SUPABASE_URL'
}
if ([string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
    $SupabaseAnonKey = Get-DotEnvValue (Join-Path $projectRoot '.env') 'SUPABASE_ANON_KEY'
}
if ([string]::IsNullOrWhiteSpace($SupabaseUrl) -or [string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
    throw 'SUPABASE_URL and SUPABASE_ANON_KEY are required. Add them to the existing .env file or pass both script parameters.'
}

try {
    $tags = Invoke-RestMethod -Uri "$OllamaUrl/api/tags" -TimeoutSec 10
} catch {
    throw "Cannot reach Ollama at $OllamaUrl. Start D:\CAIOllama\ollama.exe serve and retry."
}

$installed = @($tags.models | ForEach-Object { [string]$_.name } | Where-Object { $_ })
if ($installed.Count -eq 0) {
    throw 'No Ollama model is installed. Run: D:\CAIOllama\ollama.exe pull qwen3.5:4b'
}

if ([string]::IsNullOrWhiteSpace($Model)) {
    $Model = if ($installed -contains 'qwen3.5:4b') { 'qwen3.5:4b' } else { $installed[0] }
}
if ($installed -notcontains $Model) {
    throw "Model '$Model' is not installed. Installed models: $($installed -join ', ')"
}

$environmentFile = Join-Path $projectRoot 'supabase\functions\.env.local'
$content = @"
LOCAL_NLU_URL=http://host.docker.internal:11434
LOCAL_NLU_MODEL=$Model
LOCAL_NLU_DEBUG=true
LOCAL_NLU_REQUIRED=true
SUPABASE_URL=$SupabaseUrl
SUPABASE_ANON_KEY=$SupabaseAnonKey
INSURANCE_ASSISTANT_ALLOWED_ORIGIN=http://localhost:$FlutterPort
"@
Set-Content -LiteralPath $environmentFile -Value $content -NoNewline -Encoding utf8

$flutterFile = Join-Path $projectRoot 'local_development\flutter.local.json'
@{
    SUPABASE_URL = $SupabaseUrl
    SUPABASE_ANON_KEY = $SupabaseAnonKey
    LOCAL_INSURANCE_ASSISTANT_URL = 'http://127.0.0.1:54321/functions/v1/insurance-assistant'
} | ConvertTo-Json | Set-Content -LiteralPath $flutterFile -Encoding utf8

Write-Host "Local Edge Function configuration written to $environmentFile"
Write-Host "Flutter local configuration written to $flutterFile"
Write-Host "Ollama model selected: $Model"
Write-Host 'The file is ignored by Git and is for local development only.'

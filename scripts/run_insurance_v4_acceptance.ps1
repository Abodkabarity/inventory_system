param(
  [string[]] $CaseIds = @(),
  [switch] $Parallel
)

$ErrorActionPreference = 'Stop'

foreach ($line in Get-Content -LiteralPath '.env') {
  if ($line -match '^\s*([^#][A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') {
    $name = $Matches[1]
    $value = $Matches[2].Trim().Trim('"').Trim("'")
    Set-Item -Path "Env:$name" -Value $value
  }
}

function Get-TestUserId {
  $parts = $env:AI_TEST_JWT.Split('.')
  $payload = $parts[1].Replace('-', '+').Replace('_', '/')
  while ($payload.Length % 4 -ne 0) { $payload += '=' }
  $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
  return [string] $claims.sub
}

function New-TestHeaders {
  $userId = Get-TestUserId
  $tokenResult = (& supabase db query --linked --output-format json "select token from auth.refresh_tokens where user_id='$userId' and revoked=false order by created_at desc limit 1") | Out-String | ConvertFrom-Json
  $refresh = [string] $tokenResult.rows[0].token
  if ([string]::IsNullOrWhiteSpace($refresh)) { throw 'No active test refresh token.' }
  $session = Invoke-RestMethod -Method Post -Uri "$env:SUPABASE_URL/auth/v1/token?grant_type=refresh_token" -Headers @{
    apikey = $env:SUPABASE_ANON_KEY
    'Content-Type' = 'application/json'
  } -Body (@{ refresh_token = $refresh } | ConvertTo-Json)
  return @{
    Authorization = "Bearer $($session.access_token)"
    apikey = $env:SUPABASE_ANON_KEY
    'Content-Type' = 'application/json'
  }
}

$cases = @(
  [pscustomobject]@{ Id='A'; Q='omalizumab'; Must='omalizumab'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='B'; Q='From the approved policy, give the Mounjaro starting dose schedule and titration interval.'; Must='2.5.*4|4.*2.5'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='C'; Q='ما الحد الأدنى للعمر المذكور لعلاج الشرى المزمن التلقائي بأوماليزوماب؟'; Must='12'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='D'; Q='Which indications are explicitly listed for tirzepatide in the approved table?'; Must='Obesity|السمنة'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='E'; Q='Under what circumstances does the approved PPI policy allow coverage?'; Must='coverage|covered|PPI|proton|تغط'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='F'; Q='What evidence is required for initial approval of a GLP-1 receptor agonist?'; Must='6.5'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='G'; Q='What approved evidence is needed to continue Omalizumab treatment rather than start it?'; Must='Omalizumab'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='H'; Q='Can the first Mounjaro 2.5 mg prescription include refills?'; Must='no.{0,20}refill|not include.{0,20}refill|without.{0,20}refill|لا.*إعادة'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='I'; Q='ما المستندات المطلوبة مع طلب تغطية علاج GLP-1 حسب الملفات المعتمدة؟'; Must='تقرير|report|HbA1c'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='J'; Q='List the clinician specialties eligible under the PPI coverage document.'; Must='Otolaryngology'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='K'; Q='As an otolaryngologist, which covered treatments or policies list my specialty?'; Must='Omalizumab'; MinDocs=2; Expected='grounded' },
  [pscustomobject]@{ Id='L'; Q='Which specialties are allowed to prescribe Omalizumab according to its approved policy?'; Must='Otolaryngology'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='M'; Q='Across the approved documents, find every supported policy owner that names Otolaryngology as eligible.'; Must='PPI[\s\S]*Omalizumab|Omalizumab[\s\S]*PPI'; MinDocs=2; Expected='grounded' },
  [pscustomobject]@{ Id='N'; Q='Compare the starting doses and monthly quantity limits listed for Mounjaro and Ozempic.'; Must='Mounjaro[\s\S]*Ozempic|Ozempic[\s\S]*Mounjaro'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='O'; Q='PPI?'; Must='PPI|proton'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='P'; Q='ما شروط تغطية مثبطات مضخة البروتون كما وردت في الوثيقة؟'; Must='تغطية|PPI|مثبطات'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='Q'; Q='What does the approved Omalizumab policy say about eligible prescribers?'; Must='eligible|Otolaryngology'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='R'; Q='Mounjaro جرعة البداية والكمية الشهرية حسب policy؟'; Must='2.5'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='S'; Q='moonjaro approved-policy overview'; Must='Mounjaro'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='T'; Q='For CSU, what age condition does the Omalizumab document state?'; Must='12'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='U'; Q='A patient is age 11 with chronic spontaneous urticaria. Does the explicit Omalizumab age criterion pass?'; Must='12'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='V'; Q='Explain the alternative OR branches that can qualify a patient for initial GLP-1 coverage.'; Must='contraindication|comorbid|first-line'; MinDocs=1; Expected='grounded' },
  [pscustomobject]@{ Id='W'; Q='Do the approved insurance documents establish coverage rules for dental implants?'; Must=''; MinDocs=0; Expected='missing' },
  [pscustomobject]@{ Id='X'; Q='medicine'; Must=''; MinDocs=0; Expected='clarification' },
  [pscustomobject]@{ Id='Y'; Q='Summarize the PPI coverage policy and all supported prescriber-specialty details.'; Must='PPI'; MinDocs=1; Expected='grounded'; Feedback='incomplete' },
  [pscustomobject]@{ Id='Z'; Q='What is the approved initial-dose rule for Ozempic?'; Must='Ozempic'; MinDocs=1; Expected='grounded'; Feedback='incorrect' },
  [pscustomobject]@{ Id='AA'; Q='Which treatments are linked to the specialty Otolaryngology in approved evidence?'; Must='Omalizumab'; MinDocs=2; Expected='grounded'; Feedback='misunderstood' }
)

if ($CaseIds.Count -gt 0) {
  $cases = @($cases | Where-Object { $CaseIds -contains $_.Id })
}

$headers = New-TestHeaders
$endpoint = "$env:SUPABASE_URL/functions/v1/insurance-policy-v4"
$results = @()

if ($Parallel) {
  $results = @($cases | ForEach-Object -Parallel {
    $case = $_
    $headers = $using:headers
    $endpoint = $using:endpoint
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
      $response = Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers -Body (@{
        message = $case.Q
        branch_name = 'V4 A-AA Acceptance'
        debug = $true
      } | ConvertTo-Json)
      $timer.Stop()
      $status = [string] $response.answer_status
      $documents = @($response.citations | ForEach-Object document_title | Where-Object { $_ } | Select-Object -Unique)
      $valid = if ($case.Expected -eq 'clarification') {
        $status -eq 'clarification_required'
      } elseif ($case.Expected -eq 'missing') {
        $status -in @('insufficient_evidence', 'grounded', 'grounded_extractive', 'partial')
      } else {
        ($status -in @('grounded', 'grounded_extractive', 'partial')) -and ($response.debug.validation.valid -eq $true)
      }
      $mustPass = [string]::IsNullOrWhiteSpace($case.Must) -or ([string] $response.answer -match $case.Must)
      $documentPass = $documents.Count -ge [int] $case.MinDocs
      $tokens = 0
      foreach ($provider in @($response.debug.ai)) { $tokens += [int] ($provider.usage.total_tokens ?? 0) }
      [pscustomobject]@{
        id = $case.Id; pass = ($valid -and $mustPass -and $documentPass); status = $status
        elapsed_ms = $timer.ElapsedMilliseconds; documents = $documents; citation_count = @($response.citations).Count
        calls = @($response.debug.ai).Count; fallback_count = @($response.debug.ai | Where-Object fallback_used).Count
        token_usage = $tokens; validation_errors = @($response.debug.validation.errors)
        must_pass = $mustPass; document_pass = $documentPass; deep_review = $null; deep_ms = $null; recovery_status = $null
      }
    } catch {
      $timer.Stop()
      [pscustomobject]@{
        id = $case.Id; pass = $false; status = 'exception'; elapsed_ms = $timer.ElapsedMilliseconds; documents = @()
        citation_count = 0; calls = 0; fallback_count = 0; token_usage = 0; validation_errors = @($_.Exception.Message)
        must_pass = $false; document_pass = $false; deep_review = $null; deep_ms = $null; recovery_status = $null
      }
    }
  } -ThrottleLimit 4)
  foreach ($row in $results) {
    Write-Output ("CASE {0} pass={1} status={2} ms={3}" -f $row.id, $row.pass, $row.status, $row.elapsed_ms)
  }
  Write-Output 'BATCH_JSON'
  $results | ConvertTo-Json -Depth 8
  exit
}

foreach ($case in $cases) {
  $timer = [Diagnostics.Stopwatch]::StartNew()
  try {
    $response = Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers -Body (@{
      message = $case.Q
      branch_name = 'V4 A-AA Acceptance'
      debug = $true
    } | ConvertTo-Json)
    $timer.Stop()
    $status = [string] $response.answer_status
    $documents = @($response.citations | ForEach-Object document_title | Where-Object { $_ } | Select-Object -Unique)
    $valid = if ($case.Expected -eq 'clarification') {
      $status -eq 'clarification_required'
    } elseif ($case.Expected -eq 'missing') {
      $status -in @('insufficient_evidence', 'grounded', 'grounded_extractive', 'partial')
    } else {
      ($status -in @('grounded', 'grounded_extractive', 'partial')) -and ($response.debug.validation.valid -eq $true)
    }
    $mustPass = [string]::IsNullOrWhiteSpace($case.Must) -or ([string] $response.answer -match $case.Must)
    $documentPass = $documents.Count -ge [int] $case.MinDocs
    $pass = $valid -and $mustPass -and $documentPass
    $providers = @($response.debug.ai)
    $deepPass = $null
    $deepMs = $null
    $recoveryStatus = $null
    if ($case.PSObject.Properties.Name -contains 'Feedback') {
      $deepTimer = [Diagnostics.Stopwatch]::StartNew()
      $recovery = Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers -Body (@{
        feedback_message_id = $response.message_id
        feedback_reason = $case.Feedback
        branch_name = 'V4 A-AA Acceptance'
        debug = $true
      } | ConvertTo-Json)
      $deepTimer.Stop()
      $deepMs = $deepTimer.ElapsedMilliseconds
      $recoveryStatus = [string] $recovery.answer_status
      $deepPass = ($recovery.recovery_used -eq $true) -and ($recoveryStatus -in @('grounded', 'grounded_extractive', 'partial'))
      $pass = $pass -and $deepPass
      $providers += @($recovery.debug.ai)
    }
    $tokens = 0
    foreach ($provider in $providers) { $tokens += [int] ($provider.usage.total_tokens ?? 0) }
    $row = [pscustomobject]@{
      id = $case.Id
      pass = $pass
      status = $status
      elapsed_ms = $timer.ElapsedMilliseconds
      documents = $documents
      citation_count = @($response.citations).Count
      calls = $providers.Count
      fallback_count = @($providers | Where-Object fallback_used).Count
      token_usage = $tokens
      validation_errors = @($response.debug.validation.errors)
      must_pass = $mustPass
      document_pass = $documentPass
      deep_review = $deepPass
      deep_ms = $deepMs
      recovery_status = $recoveryStatus
    }
  } catch {
    $timer.Stop()
    $row = [pscustomobject]@{
      id = $case.Id
      pass = $false
      status = 'exception'
      elapsed_ms = $timer.ElapsedMilliseconds
      documents = @()
      citation_count = 0
      calls = 0
      fallback_count = 0
      token_usage = 0
      validation_errors = @($_.Exception.Message)
      must_pass = $false
      document_pass = $false
      deep_review = $null
      deep_ms = $null
      recovery_status = $null
    }
  }
  $results += $row
  Write-Output ("CASE {0} pass={1} status={2} ms={3}" -f $row.id, $row.pass, $row.status, $row.elapsed_ms)
}

Write-Output 'BATCH_JSON'
$results | ConvertTo-Json -Depth 8

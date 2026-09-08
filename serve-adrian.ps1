# Serves this folder over http://localhost so the mic permission Chrome grants
# actually sticks. Opening the HTML files directly (file://) makes Chrome
# re-prompt for microphone access roughly every ~60s, because Web Speech API's
# continuous mode auto-restarts on that interval and file:// origins don't
# reliably retain the "Allow" grant across those restarts. localhost is a real,
# secure origin, so the grant persists normally. No installs required — this
# uses only what ships with Windows.
#
# Double-click start-adrian.bat instead of running this file directly.

$root = $PSScriptRoot
$port = 5757
$maxAttempts = 10
$listener = $null

for ($i = 0; $i -lt $maxAttempts; $i++) {
    $candidate = $port + $i
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add("http://localhost:$candidate/")
    try {
        $l.Start()
        $listener = $l
        $port = $candidate
        break
    } catch {
        $l.Close()
    }
}

if (-not $listener) {
    Write-Host "Could not find a free port to serve on. Close other local servers and try again."
    Read-Host "Press Enter to exit"
    exit 1
}

$mime = @{
    '.html' = 'text/html'
    '.js'   = 'application/javascript'
    '.json' = 'application/json'
    '.css'  = 'text/css'
    '.svg'  = 'image/svg+xml'
    '.png'  = 'image/png'
    '.ico'  = 'image/x-icon'
    '.txt'  = 'text/plain'
}

$url = "http://localhost:$port/"
Write-Host "Serving Adrian at $url"
Write-Host "Facilitator: ${url}adrian-facilitator-v15.html"
Write-Host "Audience:    ${url}adrian-audience-v14.html"
Write-Host ""
Write-Host "Keep this window open for the whole session. Close it to stop serving."
Write-Host ""

Start-Process "${url}adrian-facilitator-v15.html"

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $req = $context.Request
        $res = $context.Response
        try {
            $relPath = [Uri]::UnescapeDataString($req.Url.AbsolutePath.TrimStart('/'))
            if ([string]::IsNullOrWhiteSpace($relPath)) { $relPath = 'adrian-facilitator-v15.html' }
            # Reject path traversal — this only ever needs to serve files inside $root.
            if ($relPath -match '\.\.') {
                $res.StatusCode = 400
            } else {
                $filePath = Join-Path $root $relPath
                if (Test-Path $filePath -PathType Leaf) {
                    $ext = [System.IO.Path]::GetExtension($filePath)
                    $contentType = $mime[$ext]
                    if (-not $contentType) { $contentType = 'application/octet-stream' }
                    $bytes = [System.IO.File]::ReadAllBytes($filePath)
                    $res.ContentType = $contentType
                    $res.ContentLength64 = $bytes.Length
                    $res.OutputStream.Write($bytes, 0, $bytes.Length)
                } else {
                    $res.StatusCode = 404
                }
            }
        } catch {
            try { $res.StatusCode = 500 } catch {}
        } finally {
            $res.OutputStream.Close()
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
}

$port = 3456
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Host "Serving $root on http://localhost:$port/"
while ($listener.IsListening) {
    $ctx  = $listener.GetContext()
    $req  = $ctx.Request
    $resp = $ctx.Response
    $path = $req.Url.LocalPath.TrimStart('/')
    if ($path -eq '') { $path = 'supercoach-draft.html' }
    $file = [System.IO.Path]::GetFullPath((Join-Path $root $path))
    # Block path traversal — resolved path must stay inside $root
    if (-not $file.StartsWith([System.IO.Path]::GetFullPath($root) + [System.IO.Path]::DirectorySeparatorChar) -and
        $file -ne [System.IO.Path]::GetFullPath($root)) {
        $resp.StatusCode = 403
        $resp.OutputStream.Close()
        continue
    }
    if (Test-Path $file -PathType Leaf) {
        $ext = [System.IO.Path]::GetExtension($file).ToLower()
        $mime = switch ($ext) {
            '.html' { 'text/html; charset=utf-8' }
            '.js'   { 'application/javascript; charset=utf-8' }
            '.css'  { 'text/css; charset=utf-8' }
            default { 'application/octet-stream' }
        }
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $resp.ContentType     = $mime
        $resp.ContentLength64 = $bytes.LongLength
        $resp.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
        $resp.StatusCode = 404
    }
    $resp.OutputStream.Flush()
    $resp.OutputStream.Close()
}

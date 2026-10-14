
$ErrorActionPreference = 'Stop'

# Base64-encoded WinRAR registration key
$keyBase64 = @'
UkFSIHJlZ2lzdHJhdGlvbiBkYXRhDQpXaW5SQVINClVubGltaXRlZCBDb21wYW55IExpY2Vuc2UN
ClVJRD00YjkxNGZiNzcyYzgzNzZiZDg3ZA0KNjQxMjIxMjI1MGQ4N2Q5ODY2YWQxMmViOWY5MDBl
ZDdkN2UxODgyMDJhOWZhOWI4MmEzMzM4DQo5NzVkZTM1MmM0NDdkZGI3ZjNhODYwZmNlNmNiNWZm
ZGU2Mjg5MDA3OTg2MWJlNTc2Mzg3MTcNCjcxMzFjZWQ4MzVlZDY1Y2M3NDNkOTc3N2YyZWE3MWE4
ZTMyYzdlNTkzY2Y2Njc5NDM0MzU2NQ0KYjQxYmNmNTY5Mjk0ODZiOGJjZGFjMzNkNTBlY2Y3NzM5
OTYwNDVmZDc1ODc0NjUxYzY5NzhjDQo1MWM4Y2MyN2ZjOWQ0MDY2ZmQxNjBlZWRmNTM1NDBkYjU1
YTcwMzM3NzFhYTVkN2M1MWQzNWUNCjY2MTEyMWY5NDljZmQ2YTA3YjZmYTUzODllNzlmZTdmMDUw
M2IxMDcwNDYyMWFkZTYwZTQwYQ0KZDY3OWM4MjU1Y2JjODMzNmY4ZTIzYzRiM2Y0NzhhNTI1NjFi
ODYzM2I0NjAxMzYyMzQ5NzczDQo=
'@

# Decode the registration key
$keyBytes = [Convert]::FromBase64String(
    ($keyBase64 -replace '\s', '')
)

# Install to current user's WinRAR directory
$keyDir = Join-Path $env:APPDATA 'WinRAR'
$keyPath = Join-Path $keyDir 'rarreg.key'

New-Item -ItemType Directory -Path $keyDir -Force | Out-Null
[System.IO.File]::WriteAllBytes($keyPath, $keyBytes)

Write-Host "[OK] WinRAR registration key installed." -ForegroundColor Green


"class TestClassRedef { }" | Out-File -Encoding utf8 ./TestClassRedef.ps1

try {
    Write-Host "First load..."
    . ./TestClassRedef.ps1
    Write-Host "Second load..."
    . ./TestClassRedef.ps1
    Write-Host "Success!"
} catch {
    Write-Host "Failed: $_"
}

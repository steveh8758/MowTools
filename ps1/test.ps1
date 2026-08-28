Add-Type -AssemblyName System.Windows.Forms

[System.Windows.Forms.MessageBox]::Show(
    "This is a test!",
    "測試",
    [System.Windows.Forms.MessageBoxButtons]::OK
)
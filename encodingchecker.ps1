param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$Input,
    
    [Parameter(Position=1, Mandatory=$true)]
    [string]$Output
)

function Get-FileEncoding {
    param(
        [string]$FilePath
    )
    
    try {
        # ファイルの最初の数バイトを読み取ってBOMを確認
        $bytes = Get-Content $FilePath -Encoding Byte -TotalCount 4 -ErrorAction Stop
        
        if ($bytes.Length -ge 3) {
            # UTF-8 BOM
            if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                return "UTF-8"
            }
        }
        
        if ($bytes.Length -ge 2) {
            # UTF-16 LE BOM
            if ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
                return "UTF-16LE"
            }
            # UTF-16 BE BOM
            if ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
                return "UTF-16BE"
            }
        }
        
        if ($bytes.Length -ge 4) {
            # UTF-32 LE BOM
            if ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00) {
                return "UTF-32LE"
            }
            # UTF-32 BE BOM
            if ($bytes[0] -eq 0x00 -and $bytes[1] -eq 0x00 -and $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF) {
                return "UTF-32BE"
            }
        }
        
        # BOMがない場合、ファイルの内容を分析
        $content = Get-Content $FilePath -Encoding Byte -TotalCount 1000 -ErrorAction Stop
        
        if ($content.Length -eq 0) {
            return "Empty"
        }
        
        # ASCIIかどうかチェック
        $isAscii = $true
        foreach ($byte in $content) {
            if ($byte -gt 127) {
                $isAscii = $false
                break
            }
        }
        
        if ($isAscii) {
            return "ASCII"
        }
        
        # UTF-8かどうかチェック（簡易判定）
        try {
            $utf8Text = [System.Text.Encoding]::UTF8.GetString($content)
            $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($utf8Text)
            
            if ($utf8Bytes.Length -eq $content.Length) {
                $match = $true
                for ($i = 0; $i -lt $content.Length; $i++) {
                    if ($utf8Bytes[$i] -ne $content[$i]) {
                        $match = $false
                        break
                    }
                }
                if ($match) {
                    return "UTF-8"
                }
            }
        }
        catch {
            # UTF-8でない
        }
        
        # Shift_JISかどうかチェック
        try {
            $sjisEncoding = [System.Text.Encoding]::GetEncoding("Shift_JIS")
            $sjisText = $sjisEncoding.GetString($content)
            $sjisBytes = $sjisEncoding.GetBytes($sjisText)
            
            if ($sjisBytes.Length -eq $content.Length) {
                $match = $true
                for ($i = 0; $i -lt $content.Length; $i++) {
                    if ($sjisBytes[$i] -ne $content[$i]) {
                        $match = $false
                        break
                    }
                }
                if ($match) {
                    return "Shift_JIS"
                }
            }
        }
        catch {
            # Shift_JISでない
        }
        
        return "Unknown"
    }
    catch {
        return "Error: $($_.Exception.Message)"
    }
}

# 入力パラメータの検証
Write-Host "入力パラメータ: Input=$Input, Output=$Output"

if (-not (Test-Path $Input)) {
    Write-Error "入力ディレクトリが存在しません: $Input"
    exit 1
}

if (-not (Test-Path $Input -PathType Container)) {
    Write-Error "入力パスがディレクトリではありません: $Input"
    exit 1
}

# 出力ディレクトリの作成（存在しない場合）
$outputDir = Split-Path $Output -Parent
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# 結果を格納する配列
$results = @()

# CSVヘッダー
$results += "Encoding,Path"

Write-Host "ファイルエンコーディングの調査を開始します..."
Write-Host "入力ディレクトリ: $Input"
Write-Host "出力ファイル: $Output"

# 指定ディレクトリ配下のすべてのファイルを再帰的に取得
$files = Get-ChildItem -Path $Input -File -Recurse -ErrorAction SilentlyContinue

$totalFiles = $files.Count
$currentFile = 0

foreach ($file in $files) {
    $currentFile++
    Write-Progress -Activity "エンコーディング調査中" -Status "進行状況: $currentFile / $totalFiles" -PercentComplete (($currentFile / $totalFiles) * 100)
    
    $encoding = Get-FileEncoding -FilePath $file.FullName
    $relativePath = $file.FullName.Replace($Input, "").TrimStart('\')
    
    # CSVに適した形式でパスを引用符で囲む（パスにカンマが含まれる場合）
    if ($file.FullName -match ',') {
        $csvPath = "`"$($file.FullName)`""
    } else {
        $csvPath = $file.FullName
    }
    
    $results += "$encoding,$csvPath"
}

Write-Progress -Activity "エンコーディング調査中" -Completed

# 結果をCSVファイルに出力
$results | Out-File -FilePath $Output -Encoding UTF8

Write-Host "調査が完了しました。"
Write-Host "結果ファイル: $Output"
Write-Host "調査対象ファイル数: $totalFiles"

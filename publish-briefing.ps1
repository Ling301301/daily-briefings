param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("news", "minerals")]
  [string]$Page,

  [Parameter(Mandatory = $true)]
  [string]$Title,

  [Parameter(Mandatory = $false)]
  [string]$MarkdownPath,

  [Parameter(ValueFromPipeline = $true)]
  [string]$InputObject
)

begin {
  $ErrorActionPreference = "Stop"
  $repo = Split-Path -Parent $MyInvocation.MyCommand.Path
  $inputLines = New-Object System.Collections.Generic.List[string]
  $updated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

process {
  if ($null -ne $InputObject) {
    $inputLines.Add($InputObject)
  }
}

end {
  function Convert-InlineMarkdown {
    param([string]$Text)
    $encoded = [System.Net.WebUtility]::HtmlEncode($Text)
    $encoded = [regex]::Replace($encoded, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
    $encoded = [regex]::Replace($encoded, '\[(?<label>[^\]]+)\]\((?<url>https?://[^\s)]+)\)', '<a href="${url}">${label}</a>')
    $encoded = [regex]::Replace($encoded, '(https?://[^\s<]+)', '<a href="$1">$1</a>')
    return $encoded
  }

  function Convert-MarkdownToHtml {
    param([string]$Markdown)

    $lines = $Markdown -split "`r?`n"
    $html = New-Object System.Collections.Generic.List[string]
    $paragraph = New-Object System.Collections.Generic.List[string]

    function Flush-Paragraph {
      if ($paragraph.Count -gt 0) {
        $joined = ($paragraph -join "<br>")
        $html.Add("<p>$joined</p>")
        $paragraph.Clear()
      }
    }

    foreach ($line in $lines) {
      $trimmed = $line.Trim()
      if ($trimmed.Length -eq 0) {
        Flush-Paragraph
        continue
      }

      if ($trimmed -match '^###\s+(.+)$') {
        Flush-Paragraph
        $html.Add("<h3>$(Convert-InlineMarkdown $Matches[1])</h3>")
        continue
      }

      if ($trimmed -match '^##\s+(.+)$') {
        Flush-Paragraph
        $html.Add("<h2>$(Convert-InlineMarkdown $Matches[1])</h2>")
        continue
      }

      if ($trimmed -match '^#\s+(.+)$') {
        Flush-Paragraph
        $html.Add("<h1>$(Convert-InlineMarkdown $Matches[1])</h1>")
        continue
      }

      if ($trimmed -match '^---+$') {
        Flush-Paragraph
        $html.Add("<hr>")
        continue
      }

      if ($trimmed -match '^[-*]\s+(.+)$') {
        Flush-Paragraph
        $html.Add("<p class=`"bullet`">$(Convert-InlineMarkdown $Matches[1])</p>")
        continue
      }

      $paragraph.Add((Convert-InlineMarkdown $trimmed))
    }

    Flush-Paragraph
    return ($html -join "`n")
  }

  $markdown = $inputLines -join "`n"
  if (-not [string]::IsNullOrWhiteSpace($MarkdownPath)) {
    $markdown = [System.IO.File]::ReadAllText($MarkdownPath, [System.Text.Encoding]::UTF8)
  }
  if ([string]::IsNullOrWhiteSpace($markdown)) {
    $markdown = [Console]::In.ReadToEnd()
  }

  $body = Convert-MarkdownToHtml $markdown
  $pageTitle = [System.Net.WebUtility]::HtmlEncode($Title)

  $htmlDoc = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$pageTitle</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <main class="page article-page">
    <nav class="top-nav"><a href="index.html">Home</a></nav>
    <article class="article">
      <p class="eyebrow">Daily Briefing</p>
      <h1>$pageTitle</h1>
      <p class="meta">Updated: $updated</p>
      <div class="briefing-body">
$body
      </div>
    </article>
  </main>
</body>
</html>
"@

  $pagePath = Join-Path $repo ($Page + ".html")
  [System.IO.File]::WriteAllText($pagePath, $htmlDoc, [System.Text.Encoding]::UTF8)

  $indexPath = Join-Path $repo "index.html"
  if (Test-Path -LiteralPath $indexPath) {
    $indexText = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)
    $indexText = [regex]::Replace($indexText, '(<time id="updated">)(.*?)(</time>)', "`$1$updated`$3")
    [System.IO.File]::WriteAllText($indexPath, $indexText, [System.Text.Encoding]::UTF8)
  }

  $gitStatus = & git -C $repo status --short
  if ($gitStatus) {
    & git -C $repo add -- $pagePath $indexPath
    try {
      & git -C $repo commit -m "Update $Page briefing"
    } catch {
      # Ignore empty-commit or no-op failures.
    }
    & git -C $repo push
  }
}

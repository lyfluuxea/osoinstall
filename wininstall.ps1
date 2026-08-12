<#
.SYNOPSIS
    一体化安装/更新/卸载脚本 (Windows PowerShell)
    管理以下 7 个组件:
      1. node          - JavaScript 运行时
      2. opencode      - AI 编码助手终端工具
      3. oh-my-openagent - OpenCode 超能力插件 (OMO Ultimate)
      4. openspec      - 规范驱动开发框架
      5. superpowers   - 软件工程方法论技能集
      6. codegraph     - 代码图 MCP 服务器（opencode 集成）
      7. openspec-superpowers-opencode (oso) - OpenSpec + Superpowers 桥接工具

.DESCRIPTION
    全程自动安装，无需手动干预。
    输出语言: 简体中文
    支持指定单个或多个组件操作。

.PARAMETER Action
    install   - 安装组件（默认）
    update    - 更新组件
    uninstall - 卸载组件

.PARAMETER Component
    要操作的组件，使用 --组件名 格式，可指定多个。默认全部 7 个。
    有效值: --node, --opencode, --oh-my-openagent, --openspec, --superpowers, --codegraph, --oso

.EXAMPLE
    .\install.ps1                                    # 安装所有组件
    .\install.ps1 install                            # 同上
    .\install.ps1 update                             # 更新所有组件
    .\install.ps1 uninstall                          # 卸载所有组件
    .\install.ps1 install --node --opencode          # 安装 node 和 opencode
    .\install.ps1 update --openspec                  # 仅更新 openspec
    .\install.ps1 uninstall --oso                    # 卸载 oso
    .\install.ps1 --node                             # 安装 (默认) node
#>

param(
    [string]$Action = 'install',
    [switch]$Help
)

#Requires -Version 5.1

# ─── 路径常量 ────────────────────────────────────────────────────────────────
$OPENCODE_CONFIG_DIR = "$env:USERPROFILE\.config\opencode"
$OPENCODE_JSON = Join-Path $OPENCODE_CONFIG_DIR "opencode.json"
$OMO_CONFIG_DIR = "$env:USERPROFILE\.omo"
$OPENCODE_PLUGIN_SUPERPOWERS = "superpowers@git+https://github.com/obra/superpowers.git"

# 有效组件列表
$VALID_COMPONENTS = @('node', 'opencode', 'oh-my-openagent', 'openspec', 'superpowers', 'codegraph', 'oso')

# 从 $args 中解析 --组件 标志
if ($args.Count -gt 0) {
    $Component = @()
    foreach ($a in $args) {
        if ($a -match '^-{1,2}(.+)$') {
            $Component += $matches[1]
        }
        else {
            Write-Warn "忽略未知参数: $a"
        }
    }
}
else {
    $Component = $VALID_COMPONENTS
}

# ─── 颜色支持 ────────────────────────────────────────────────────────────────
$Host.UI.RawUI.ForegroundColor = [ConsoleColor]::White

function Write-Info {
    Write-Host "[信息]" -ForegroundColor Cyan -NoNewline
    Write-Host " $args"
}

function Write-Success {
    Write-Host "[成功]" -ForegroundColor Green -NoNewline
    Write-Host " $args"
}

function Write-Warn {
    Write-Host "[警告]" -ForegroundColor Yellow -NoNewline
    Write-Host " $args"
}

function Write-Error {
    Write-Host "[错误]" -ForegroundColor Red -NoNewline
    Write-Host " $args"
}

function Write-Step {
    Write-Host ""
    Write-Host "━━━ $args ━━━" -ForegroundColor Magenta
}

function Write-Banner {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
    Write-Host "  $args" -ForegroundColor Blue
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
    Write-Host ""
}

# ─── 辅助函数 ────────────────────────────────────────────────────────────────
function Test-Command($cmd) {
    return (Get-Command $cmd -ErrorAction SilentlyContinue) -ne $null
}

function Get-ComponentLabel($comp) {
    switch ($comp) {
        'node'            { return 'Node.js' }
        'opencode'        { return 'opencode' }
        'oh-my-openagent' { return 'oh-my-openagent' }
        'openspec'        { return 'openspec' }
        'superpowers'     { return 'superpowers' }
        'codegraph'       { return 'codegraph' }
        'oso'             { return 'openspec-superpowers-opencode (oso)' }
    }
}

# 通用函数：向 opencode.json 的 plugin 数组添加条目
# 返回值：$true=已添加, $false=已存在或失败
function Add-JsonPlugin($entry) {
    $file = $OPENCODE_JSON
    if (-not (Test-Path $OPENCODE_CONFIG_DIR)) {
        New-Item -ItemType Directory -Path $OPENCODE_CONFIG_DIR -Force | Out-Null
    }
    # 处理不存在或空文件
    if (-not (Test-Path $file) -or (Get-Item $file).Length -eq 0) {
        @{ plugin = @($entry) } | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path $file
        return $true
    }
    try {
        $cfg = Get-Content $file -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($null -eq $cfg.plugin) {
            $cfg | Add-Member -MemberType NoteProperty -Name 'plugin' -Value @() -Force
        }
        # 精确匹配 + 前缀匹配（解决 name 与 name@version 重复问题）
        $alreadyExists = ($cfg.plugin -contains $entry) -or
                         ($cfg.plugin | Where-Object { $_ -like "$entry@*" })
        if (-not $alreadyExists) {
            $cfg.plugin += $entry
            $cfg | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path $file
            return $true
        }
        return $false  # 已存在
    }
    catch {
        Write-Warn "opencode.json 解析失败，重新创建: $_"
        @{ plugin = @($entry) } | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path $file
        return $true
    }
}

# 清理 opencode 插件缓存目录（安装/更新前强制拉取最新，卸载后清理残留）
function Clear-OpencodePackageCache($pattern) {
    $cacheDir = Join-Path $env:USERPROFILE ".cache\opencode\packages"
    if (Test-Path $cacheDir) {
        $cacheItems = Get-ChildItem $cacheDir -Filter "$pattern*" -ErrorAction SilentlyContinue
        if ($cacheItems) {
            Write-Info "清理插件缓存: $cacheDir\$pattern*"
            $cacheItems | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ─── 系统依赖: Git 与 GitHub CLI (gh) ─────────────────────────────────────────
# Git 官方安装方式参考: https://git-scm.com/download/win
function Install-Git {
    if (Test-Command git) {
        $ver = & git --version 2>$null | Select-Object -First 1
        Write-Success "git 已安装 ($ver)"
        return $true
    }

    Write-Info "正在安装 Git..."

    # 方式 1: winget
    if (Test-Command winget) {
        try {
            & winget install --id Git.Git --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
                if (Test-Command git) {
                    Write-Success "Git 安装完成 ($(& git --version 2>$null | Select-Object -First 1))"
                    return $true
                }
            }
        }
        catch {
            Write-Warn "winget 安装失败，尝试备用方案..."
        }
    }

    # 方式 2: 直接下载 Git for Windows 安装器
    Write-Info "正在从 GitHub 下载 Git for Windows..."
    try {
        $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest" -UseBasicParsing
        $asset = $latest.assets | Where-Object { $_.name -match '^Git-.*-64-bit\.exe$' } | Select-Object -First 1
        if (-not $asset) {
            throw "未找到 64 位安装包"
        }
        $installer = Join-Path $env:TEMP "git-installer.exe"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installer -UseBasicParsing
        Start-Process $installer -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /SUPPRESSMSGBOXES /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS" -Wait
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
        if (Test-Command git) {
            Write-Success "Git 安装完成 ($(& git --version 2>$null | Select-Object -First 1))"
            return $true
        }
    }
    catch {
        Write-Warn "Git 下载/安装失败: $_"
    }

    Write-Warn "git 安装失败。请手动安装: https://git-scm.com/download/win"
    return $false
}

# GitHub CLI 官方安装方式参考: https://cli.github.com/
function Install-GH {
    if (Test-Command gh) {
        $ver = (& gh --version 2>$null | Select-Object -First 1)
        Write-Success "gh 已安装 ($ver)"
        return $true
    }

    Write-Info "正在安装 GitHub CLI (gh)..."

    # 方式 1: winget
    if (Test-Command winget) {
        try {
            & winget install --id GitHub.cli --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
                if (Test-Command gh) {
                    Write-Success "gh 安装完成 ($(& gh --version 2>$null | Select-Object -First 1))"
                    return $true
                }
            }
        }
        catch {
            Write-Warn "winget 安装失败，尝试备用方案..."
        }
    }

    # 方式 2: 直接下载 MSI
    Write-Info "正在从 GitHub 下载 gh MSI..."
    try {
        $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/cli/cli/releases/latest" -UseBasicParsing
        $asset = $latest.assets | Where-Object { $_.name -match 'windows_amd64\.msi$' } | Select-Object -First 1
        if (-not $asset) {
            throw "未找到 windows amd64 MSI 安装包"
        }
        $installer = Join-Path $env:TEMP "gh-installer.msi"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installer -UseBasicParsing
        Start-Process msiexec.exe -ArgumentList "/i `"$installer`" /quiet /norestart" -Wait
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
        if (Test-Command gh) {
            Write-Success "gh 安装完成 ($(& gh --version 2>$null | Select-Object -First 1))"
            return $true
        }
    }
    catch {
        Write-Warn "gh 下载/安装失败: $_"
    }

    Write-Warn "gh 安装失败。请手动安装: https://cli.github.com/"
    return $false
}

# ─── 组件 1: Node.js ────────────────────────────────────────────────────────
function Install-Node {
    Write-Step "组件: Node.js"

    if (Test-Command node) {
        $ver = node --version
        $majorVer = [int]($ver -replace 'v', '' -replace '\..*', '')
        Write-Info "Node.js 已安装: $ver"

        if ($majorVer -ge 18) {
            Write-Success "Node.js 版本满足要求 (>=18)"
            return $true
        }
        else {
            Write-Warn "Node.js 版本过低 (当前: $ver, 需要 >=18)"
        }
    }

    # 尝试使用 winget 安装 Node.js LTS
    if (Test-Command winget) {
        Write-Info "使用 winget 安装 Node.js 22 LTS..."
        try {
            $result = & winget install "OpenJS.NodeJS.LTS" --accept-source-agreements --accept-package-agreements 2>&1
            if ($LASTEXITCODE -eq 0) {
                $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
                Write-Success "Node.js 安装完成"
                return $true
            }
        }
        catch {
            Write-Warn "winget 安装失败，尝试备用方案..."
        }
    }

    # 备用: 使用 choco
    if (Test-Command choco) {
        Write-Info "使用 Chocolatey 安装 Node.js LTS..."
        try {
            & choco install nodejs-lts -y --no-progress 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
                Write-Success "Node.js 安装完成"
                return $true
            }
        }
        catch {
            Write-Warn "Chocolatey 安装失败"
        }
    }

    # 直接下载安装
    Write-Info "正在从 nodejs.org 下载 Node.js 22 LTS..."
    $url = "https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi"
    $installer = Join-Path $env:TEMP "node-installer.msi"

    try {
        Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
        Write-Info "正在安装..."
        Start-Process msiexec.exe -ArgumentList "/i `"$installer`" /quiet /norestart" -Wait
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

        if (Test-Command node) {
            Write-Success "Node.js $(node --version) 安装完成"
            return $true
        }
    }
    catch {
        Write-Error "Node.js 下载/安装失败: $_"
    }

    # 再次刷新 PATH
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

    if (Test-Command node) {
        Write-Success "Node.js $(node --version) 就绪"
        return $true
    }

    Write-Error "Node.js 安装失败。请手动安装: https://nodejs.org/"
    return $false
}

# ─── 组件 2: opencode ────────────────────────────────────────────────────────
function Install-OpenCode {
    Write-Step "组件: opencode"

    if (Test-Command opencode) {
        $ver = & opencode --version 2>$null
        Write-Info "opencode 已安装: $ver"

        if ($Action -eq 'update') {
            Write-Info "正在更新 opencode..."
            & npm install -g opencode-ai@latest 2>&1 | Out-Null
            $newVer = & opencode --version 2>$null
            Write-Success "opencode 已更新至 $newVer"
        }
        else {
            Write-Success "opencode 已安装，跳过"
        }
        return $true
    }

    Write-Info "正在安装 opencode..."
    & npm install -g opencode-ai@latest 2>&1 | Out-Null

    if (Test-Command opencode) {
        $ver = & opencode --version 2>$null
        Write-Success "opencode $ver 安装完成"
        return $true
    }

    Write-Error "opencode 安装失败。请手动安装: npm install -g opencode-ai"
    return $false
}

# ─── 组件 3: oh-my-openagent ────────────────────────────────────────────────
function Set-OhMyOpenAgentModel {
    $modelConfig = @{
        model = "opencode/deepseek-v4-flash-free"
        variant = "max"
        fallback_models = @(
            @{ model = "opencode/big-pickle"; variant = "high" }
            @{ model = "opencode/minimax-m2.5-free"; variant = "max" }
            @{ model = "opencode/nemotron3-superfree"; variant = "max" }
        )
        prompt_append = "所有回复、思考过程、工具调用参数及描述，全部必须使用中文。不允许出现英文回复（代码本身、库名、专有名词除外）。"
    }

    # 新统一配置文件优先，旧版遗留文件兼容
    $newBaseNames = @('omo')
    $legacyBaseNames = @('oh-my-openagent', 'oh-my-opencode')
    $extensions = @('.jsonc', '.json')
    $files = foreach ($bn in $newBaseNames) {
        foreach ($ext in $extensions) {
            Join-Path $OMO_CONFIG_DIR "$bn$ext"
        }
    }
    $files += foreach ($bn in $legacyBaseNames) {
        foreach ($ext in $extensions) {
            Join-Path $OPENCODE_CONFIG_DIR "$bn$ext"
        }
    }

    foreach ($file in $files) {
        if (-not (Test-Path $file)) { continue }

        try {
            $raw = Get-Content $file -Raw -ErrorAction Stop
            $clean = $raw -replace '(?m)^\s*//.*$', ''
            $cfg = $clean | ConvertFrom-Json
        } catch {
            Write-Warn "无法解析 $(Split-Path $file -Leaf)，跳过模型配置更新"
            continue
        }

        $changed = $false

        # 处理 [opencode] 包装结构或顶层的 agents/categories
        $targets = @()
        if ($null -ne $cfg.'[opencode]') {
            # 新版 omo.jsonc 使用 [opencode] 作顶层键
            if ($null -ne $cfg.'[opencode]'.agents) { $targets += $cfg.'[opencode]'.agents }
            if ($null -ne $cfg.'[opencode]'.categories) { $targets += $cfg.'[opencode]'.categories }
        } else {
            # 旧版直接用顶层 agents/categories
            if ($null -ne $cfg.agents) { $targets += $cfg.agents }
            if ($null -ne $cfg.categories) { $targets += $cfg.categories }
        }

        foreach ($target in $targets) {
            if ($target -is [PSCustomObject]) {
                foreach ($prop in $target.PSObject.Properties) {
                    if ($prop.Value -is [PSCustomObject]) {
                        $prop.Value | Add-Member -NotePropertyMembers $modelConfig -Force
                        $changed = $true
                    }
                }
            }
        }

        if ($changed) {
            $cfg | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path $file
            Write-Info "已更新 $(Split-Path $file -Leaf) 模型配置"
        }
    }
}

function Install-OhMyOpenAgent {
    Write-Step "组件: oh-my-openagent"

    # 确保 Bun 可用
    if (-not (Test-Command bun)) {
        Write-Info "正在安装 Bun..."
        try {
            & powershell -NoProfile -InputFormat None -ExecutionPolicy Bypass -Command "irm bun.sh/install.ps1 | iex" 2>&1 | Out-Null
        }
        catch {
            Write-Warn "Bun 安装脚本执行失败: $_"
        }

        $bunPath = Join-Path $env:USERPROFILE ".bun\bin\bun.exe"
        if (Test-Path $bunPath) {
            $env:Path = "$(Join-Path $env:USERPROFILE '.bun\bin');$env:Path"
            [Environment]::SetEnvironmentVariable("Path", $env:Path, "User")
        }
    }

    if (-not (Test-Command bun)) {
        Write-Error "Bun 安装失败。请手动安装: https://bun.sh/"
        return $false
    }

    $bunVer = & bun --version
    Write-Info "Bun $bunVer 就绪"

    # 检查 oh-my-openagent 是否已安装（精确匹配 plugin 数组）
    $omoInstalled = $false
    if (Test-Path $OPENCODE_JSON) {
        try {
            $cfg = Get-Content $OPENCODE_JSON -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
            if ($null -ne $cfg.plugin -and $cfg.plugin -contains 'oh-my-openagent') {
                $omoInstalled = $true
            }
        } catch {
            # JSON 解析失败，视为未安装
        }
    }

    if ($omoInstalled) {
        Write-Info "oh-my-openagent 已注册到 opencode"

        if ($Action -eq 'update') {
            Write-Info "正在更新 oh-my-openagent..."
            Clear-OpencodePackageCache 'oh-my-openagent'
            & bun x oh-my-openagent install --no-tui --platform=opencode `
                --claude=no --openai=no --gemini=no --copilot=no `
                --opencode-zen=yes --zai-coding-plan=no --opencode-go=no `
                --kimi-for-coding=no --vercel-ai-gateway=no 2>&1 | Out-Null
            Set-OhMyOpenAgentModel
            Write-Success "oh-my-openagent 更新完成"
        }
        else {
            Write-Success "oh-my-openagent 已安装，跳过"
        }
        return $true
    }

    Write-Info "正在安装 oh-my-openagent..."
    Clear-OpencodePackageCache 'oh-my-openagent'
    if (-not (Test-Path $OPENCODE_CONFIG_DIR)) {
        New-Item -ItemType Directory -Path $OPENCODE_CONFIG_DIR -Force | Out-Null
    }

    & bun x oh-my-openagent install --no-tui --platform=opencode `
        --claude=no --openai=no --gemini=no --copilot=no `
        --opencode-zen=yes --zai-coding-plan=no --opencode-go=no `
        --kimi-for-coding=no --vercel-ai-gateway=no 2>&1 | Out-Null

    # 备用：确保注册到 opencode.json
    Add-JsonPlugin 'oh-my-openagent' | Out-Null

    Set-OhMyOpenAgentModel

    Write-Success "oh-my-openagent 安装完成"
    return $true
}

# ─── 组件 4: openspec ────────────────────────────────────────────────────────
function Install-OpenSpec {
    Write-Step "组件: openspec"

    if (Test-Command openspec) {
        $ver = & openspec --version 2>$null
        Write-Info "openspec 已安装: $ver"

        if ($Action -eq 'update') {
            Write-Info "正在更新 openspec..."
            & npm install -g @fission-ai/openspec@latest 2>&1 | Out-Null
            Write-Success "openspec 已更新"
        }
        else {
            Write-Success "openspec 已安装，跳过"
        }
        return $true
    }

    Write-Info "正在安装 openspec..."
    & npm install -g @fission-ai/openspec@latest 2>&1 | Out-Null

    if (Test-Command openspec) {
        Write-Success "openspec 安装完成"
        return $true
    }

    Write-Error "openspec 安装失败。请手动安装: npm install -g @fission-ai/openspec@latest"
    return $false
}

# ─── 组件 5: superpowers ─────────────────────────────────────────────────────
function Install-Superpowers {
    Write-Step "组件: superpowers"

    $installed = $false
    if (Test-Path $OPENCODE_JSON) {
        try {
            $cfg = Get-Content $OPENCODE_JSON -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
            if ($null -ne $cfg.plugin -and $cfg.plugin -contains $OPENCODE_PLUGIN_SUPERPOWERS) {
                $installed = $true
            }
        } catch {
            # JSON 解析失败，不修改文件
        }
    }

    if ($installed) {
        Write-Info "superpowers 已注册到 opencode"

        if ($Action -eq 'update') {
            Write-Info "正在更新 superpowers..."
            Clear-OpencodePackageCache 'superpowers'
            Write-Info "缓存已清理，重启 OpenCode 后自动拉取最新版本"
        }
        else {
            Write-Success "superpowers 已安装，跳过"
        }
        return $true
    }

    Write-Info "正在安装 superpowers..."
    Clear-OpencodePackageCache 'superpowers'

    $added = Add-JsonPlugin $OPENCODE_PLUGIN_SUPERPOWERS
    if ($added) {
        Write-Success "superpowers 已添加到 opencode.json"
    }

    Write-Success "superpowers 安装完成"
    Write-Info "重启 OpenCode 后 superpowers 将自动加载"
    return $true
}

# ─── 组件 6: codegraph ──────────────────────────────────────────────────────
function Install-CodeGraph {
    Write-Step "组件: codegraph"

    if (Test-Command codegraph) {
        $ver = & codegraph --version 2>$null
        Write-Info "codegraph 已安装: $ver"

        if ($Action -eq 'update') {
            Write-Info "正在更新 codegraph..."
            & codegraph upgrade 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "codegraph upgrade 失败，回退 npm 更新..."
                & npm install -g @colbymchenry/codegraph@latest 2>&1 | Out-Null
                & codegraph install --target opencode --location global -y 2>&1 | Out-Null
            }
            Write-Success "codegraph 已更新"
        }
        else {
            Write-Success "codegraph 已安装，跳过"
        }
        return $true
    }

    Write-Info "正在安装 codegraph..."
    & npm install -g @colbymchenry/codegraph 2>&1 | Out-Null

    if (Test-Command codegraph) {
        Write-Info "正在注册 codegraph 到 opencode..."
        & codegraph install --target opencode --location global -y 2>&1 | Out-Null
        Write-Success "codegraph 安装完成"
        return $true
    }

    Write-Error "codegraph 安装失败。请手动安装: npm install -g @colbymchenry/codegraph"
    return $false
}

# ─── 组件 7: openspec-superpowers-opencode (oso) ────────────────────────────
# 安装 PowerShell Core (pwsh) - oso 的运行时依赖
function Install-Pwsh {
    if (Test-Command pwsh) {
        $pwshVer = & pwsh --version 2>$null
        Write-Info "pwsh 已安装: $pwshVer"
        return $true
    }

    Write-Info "正在安装 pwsh (PowerShell Core)..."
    $pwshInstalled = $false

    # 方式 1: winget
    if (Test-Command winget) {
        try {
            & winget install Microsoft.PowerShell --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $pwshInstalled = $true
            }
        }
        catch { }
    }

    # 方式 2: 直接下载 MSI
    if (-not $pwshInstalled) {
        try {
            $url = "https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-x64.msi"
            $installer = Join-Path $env:TEMP "pwsh-installer.msi"
            Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
            Start-Process msiexec.exe -ArgumentList "/i `"$installer`" /quiet /norestart" -Wait
            $pwshInstalled = $true
        }
        catch {
            Write-Warn "pwsh MSI 下载/安装失败: $_"
        }
    }

    # 刷新 PATH
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

    if (Test-Command pwsh) {
        $pwshVer = & pwsh --version 2>$null
        Write-Success "pwsh $pwshVer 安装完成"
        return $true
    }

    Write-Warn "pwsh 安装失败，oso 可能无法正常运行"
    Write-Warn "请手动安装: https://github.com/PowerShell/PowerShell/releases"
    return $false
}

function Install-OSO {
    Write-Step "组件: openspec-superpowers-opencode (oso)"

    Install-Pwsh | Out-Null

    if (Test-Command openspec-superpowers-opencode) {
        $ver = & openspec-superpowers-opencode --version 2>$null
        Write-Info "oso 已安装: $ver"

        if ($Action -eq 'update') {
            Write-Info "正在更新 oso..."
            & npm update -g @moyaspace/openspec-superpowers-opencode 2>&1 | Out-Null
            Write-Success "oso 已更新"
        }
        else {
            Write-Success "oso 已安装，跳过"
        }
        return $true
    }

    Write-Info "正在安装 openspec-superpowers-opencode..."
    & npm install -g @moyaspace/openspec-superpowers-opencode 2>&1 | Out-Null

    if (Test-Command openspec-superpowers-opencode) {
        Write-Success "openspec-superpowers-opencode 安装完成"
        return $true
    }

    Write-Error "openspec-superpowers-opencode 安装失败"
    Write-Error "请手动安装: npm install -g @moyaspace/openspec-superpowers-opencode"
    return $false
}

# ─── 卸载函数 ────────────────────────────────────────────────────────────────
function Uninstall-Node {
    Write-Info "正在卸载 Node.js..."

    if (Test-Command winget) {
        try { & winget uninstall "OpenJS.NodeJS.LTS" --silent 2>&1 | Out-Null } catch { }
    }
    if (Test-Command choco) {
        try { & choco uninstall nodejs-lts -y --no-progress 2>&1 | Out-Null } catch { }
    }

    Write-Success "Node.js 已卸载"
}

function Uninstall-OpenCode {
    if (-not (Test-Command opencode)) {
        Write-Info "opencode 未安装"
        return $true
    }

    Write-Info "正在卸载 opencode..."

    # 卸载 npm 全局包，检查返回值
    & npm uninstall -g opencode-ai 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "npm uninstall 失败 (exit: $LASTEXITCODE)，可能权限不足"
    }

    # 清理配置目录
    if (Test-Path $OPENCODE_CONFIG_DIR) {
        Remove-Item -Path $OPENCODE_CONFIG_DIR -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 保留 opencode 缓存目录（含插件缓存与用户数据），不随卸载删除

    # 验证
    Start-Sleep -Milliseconds 500
    if (Test-Command opencode) {
        Write-Warn "opencode 仍可执行，请尝试以管理员身份运行此脚本"
        return $false
    }

    Write-Success "opencode 已卸载"
    return $true
}

function Uninstall-OhMyOpenAgent {
    Write-Info "正在卸载 oh-my-openagent..."

    if (Test-Path $OPENCODE_JSON) {
        try {
            $cfg = Get-Content $OPENCODE_JSON -Raw | ConvertFrom-Json
            $cfg.plugin = @($cfg.plugin | Where-Object { $_ -notmatch 'oh-my-openagent' })
            $cfg | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path $OPENCODE_JSON
        }
        catch { }
    }

    foreach ($ext in @('.jsonc', '.json')) {
        Remove-Item (Join-Path $OPENCODE_CONFIG_DIR "oh-my-openagent$ext") -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $OPENCODE_CONFIG_DIR "oh-my-opencode$ext") -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $OMO_CONFIG_DIR "omo$ext") -ErrorAction SilentlyContinue
    }
    if (Test-Path $OMO_CONFIG_DIR) {
        $null = Remove-Item $OMO_CONFIG_DIR -ErrorAction SilentlyContinue
    }

    Clear-OpencodePackageCache 'oh-my-openagent'

    Write-Success "oh-my-openagent 已卸载"
}

function Uninstall-OpenSpec {
    if (-not (Test-Command openspec)) {
        Write-Info "openspec 未安装"
        return $true
    }
    Write-Info "正在卸载 openspec..."
    & npm uninstall -g @fission-ai/openspec 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "npm uninstall 失败 (exit: $LASTEXITCODE)，可能权限不足"
        return $false
    }
    Write-Success "openspec 已卸载"
    return $true
}

function Uninstall-Superpowers {
    Write-Info "正在卸载 superpowers..."

    if (Test-Path $OPENCODE_JSON) {
        try {
            $cfg = Get-Content $OPENCODE_JSON -Raw | ConvertFrom-Json
            $cfg.plugin = @($cfg.plugin | Where-Object { $_ -notmatch 'superpowers' })
            $cfg | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path $OPENCODE_JSON
        }
        catch { }
    }

    Clear-OpencodePackageCache 'superpowers'

    Write-Success "superpowers 已卸载"
}

function Uninstall-CodeGraph {
    if (-not (Test-Command codegraph)) {
        Write-Info "codegraph 未安装"
        return $true
    }

    Write-Info "正在卸载 codegraph..."
    # 先移除 opencode 集成配置（--keep-cli 保留 CLI 以便继续执行）
    & codegraph uninstall --target opencode --location global -y --keep-cli 2>&1 | Out-Null
    # 再卸载 npm 全局包（npm 包的 preuninstall 钩子会自动清理其余 global 配置）
    & npm uninstall -g @colbymchenry/codegraph 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "npm uninstall 失败 (exit: $LASTEXITCODE)，可能权限不足"
        return $false
    }
    Write-Success "codegraph 已卸载"
    return $true
}

function Uninstall-OSO {
    if (-not (Test-Command openspec-superpowers-opencode)) {
        Write-Info "openspec-superpowers-opencode 未安装"
        return $true
    }
    Write-Info "正在卸载 openspec-superpowers-opencode..."
    & npm uninstall -g @moyaspace/openspec-superpowers-opencode 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "npm uninstall 失败 (exit: $LASTEXITCODE)，可能权限不足"
        return $false
    }
    Write-Success "openspec-superpowers-opencode 已卸载"
    return $true
}

# ─── 路由函数 ────────────────────────────────────────────────────────────────
function Run-Install($comp) {
    switch ($comp) {
        'node'            { Install-Node }
        'opencode'        { Install-OpenCode }
        'oh-my-openagent' { Install-OhMyOpenAgent }
        'openspec'        { Install-OpenSpec }
        'superpowers'     { Install-Superpowers }
        'codegraph'       { Install-CodeGraph }
        'oso'             { Install-OSO }
    }
}

function Run-Uninstall($comp) {
    switch ($comp) {
        'node'            { Uninstall-Node }
        'opencode'        { Uninstall-OpenCode }
        'oh-my-openagent' { Uninstall-OhMyOpenAgent }
        'openspec'        { Uninstall-OpenSpec }
        'superpowers'     { Uninstall-Superpowers }
        'codegraph'       { Uninstall-CodeGraph }
        'oso'             { Uninstall-OSO }
    }
}

# ─── 主流程 ──────────────────────────────────────────────────────────────────
function Show-Usage {
    Write-Host ""
    Write-Host "用法: .\install.ps1 [操作] [--组件名...]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  操作 (默认: install):"
    Write-Host "    install   - 安装组件"
    Write-Host "    update    - 更新组件"
    Write-Host "    uninstall - 卸载组件"
    Write-Host ""
    Write-Host "  组件 (默认: 全部 7 个):"
    Write-Host "    --node              Node.js 运行时"
    Write-Host "    --opencode          AI 编码助手"
    Write-Host "    --oh-my-openagent   OpenCode 超能力插件"
    Write-Host "    --openspec          规范驱动开发框架"
    Write-Host "    --superpowers       软件工程方法论"
    Write-Host "    --codegraph         代码图 MCP 服务器"
    Write-Host "    --oso               OpenSpec+Superpowers 桥接工具"
    Write-Host ""
    Write-Host "  示例:"
    Write-Host "    .\install.ps1                                    # 安装所有组件"
    Write-Host "    .\install.ps1 install --node --opencode          # 安装 node 和 opencode"
    Write-Host "    .\install.ps1 update --openspec                  # 仅更新 openspec"
    Write-Host "    .\install.ps1 uninstall --oso                    # 卸载 oso"
    Write-Host "    .\install.ps1 --node                             # 安装 (默认) node"
    Write-Host "    .\install.ps1 uninstall                          # 卸载所有组件"
}

function Main {
    Clear-Host

    if ($Help -or $Action -eq 'help' -or $Action -eq '--help' -or $Action -eq '-h') {
        Show-Usage
        return
    }

    # 校验操作
    if ($Action -notin @('install', 'update', 'uninstall')) {
        Write-Error "无效的操作: $Action，有效值: install, update, uninstall"
        Show-Usage
        return
    }

    # 校验组件名
    $invalid = $Component | Where-Object { $_ -notin $VALID_COMPONENTS }
    if ($invalid) {
        Write-Error "无效的组件名: $($invalid -join ', ')"
        Write-Error "有效组件: $($VALID_COMPONENTS -join ', ')"
        return
    }

    if ($Action -eq 'uninstall') {
        if ($Component.Count -eq $VALID_COMPONENTS.Count) {
            Write-Banner "开始卸载所有组件"
        }
        else {
            $labels = $Component | ForEach-Object { Get-ComponentLabel $_ }
            Write-Banner "开始卸载组件: $($labels -join ', ')"
        }

        $uninstallOrder = @($Component)
        [array]::Reverse($uninstallOrder)
        foreach ($comp in $uninstallOrder) {
            Run-Uninstall $comp
        }

        Write-Banner "指定组件卸载完成！"
        return
    }

    $actionLabel = if ($Action -eq 'update') { "更新" } else { "安装" }

    if ($Component.Count -eq $VALID_COMPONENTS.Count) {
        Write-Banner "开始${actionLabel}全部 7 个组件"
    }
    else {
        $labels = $Component | ForEach-Object { Get-ComponentLabel $_ }
        Write-Banner "开始${actionLabel}组件: $($labels -join ', ')"
    }
    Write-Host ""
    Write-Info "开始时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host ""

    # 安装全部组件时检查系统依赖 (git, gh)
    if ($Component.Count -eq $VALID_COMPONENTS.Count) {
        Write-Step "检查系统依赖..."
        $null = Install-Git
        $null = Install-GH
        Write-Host ""
    }

    # 检查 npm
    if (-not (Test-Command npm)) {
        Write-Info "npm 未找到，先安装 Node.js..."
        if (-not (Install-Node)) {
            Write-Error "Node.js 安装失败，无法继续"
            return
        }
    }
    else {
        Write-Info "npm 就绪 ($(npm --version))"
    }

    foreach ($comp in $Component) {
        Run-Install $comp
    }

    # opencode 初始化并测试（仅含 superpowers 或 oso 时）
    if ($Component -contains 'superpowers' -or $Component -contains 'oso') {
        if (Test-Command opencode) {
            Write-Info "opencode初始化并测试"
            $null = & opencode run "hello" --model opencode/deepseek-v4-flash-free 2>&1
        }
    }

    Write-Host ""
    Write-Banner "指定组件${actionLabel}完成！"
    Write-Host ""
    Write-Success "运行命令 'opencode run ""hello"" --model opencode/deepseek-v4-flash-free' 测试 opencode"
    Write-Success "在项目目录运行 'openspec-superpowers-opencode init' 初始化 oso"
    Write-Host ""
    Write-Info "完成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
}

# ─── 入口 ─────────────────────────────────────────────────────────────────────
Main

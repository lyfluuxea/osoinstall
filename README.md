# OpenCode 开发环境一键安装/卸载工具

三个脚本用于自动化安装和卸载 OpenCode 开发环境所需的 7 个核心组件：

| 平台 | 脚本 | 说明 |
|------|------|------|
| **Windows** | `wininstall.ps1` | PowerShell 脚本 |
| **Linux** | `linuxinstall.sh` | Linux 安装脚本（bash 4+） |
| **macOS** | `macinstall.sh` | macOS 安装脚本（兼容 bash 3.2 / 4+） |

## 组件列表

| 组件 | 命令行标志 | 说明 |
|------|-----------|------|
| **Node.js** | `--node` | JavaScript 运行时（>=18），opencode 和 npm 包的运行基础 |
| **opencode** | `--opencode` | OpenCode CLI 主程序，AI 编程助手核心 |
| **oh-my-openagent** | `--oh-my-openagent` | 智能代理系统，自动配置 agents 和 categories 模型参数 |
| **openspec** | `--openspec` | OpenSpec 规范框架 |
| **superpowers** | `--superpowers` | 软件工程方法论技能集（OpenCode 插件） |
| **codegraph** | `--codegraph` | 代码图 MCP 服务器（opencode 集成，参考 [colbymchenry/codegraph](https://github.com/colbymchenry/codegraph)） |
| **openspec-superpowers-opencode (oso)** | `--oso` | OpenSpec + Superpowers 桥接工具 |

**依赖关系（安装顺序 → 卸载反序）：**

```
Node.js → opencode → oh-my-openagent → openspec → superpowers → codegraph → oso
```

## 系统要求

### Windows
- Windows 10/11
- PowerShell 5.1+
- 管理员权限（安装 Node.js、npm 全局包时需要）
- 首次执行需设置 PowerShell 执行策略：`Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`
- winget（可选，推荐用于自动安装 Node.js）
- gh（可选，GitHub CLI；安装全部组件时若缺失，脚本会通过 winget 或 MSI 自动安装：https://cli.github.com/）

### Linux
- bash 4+
- curl
- npm（脚本会自动通过 Node.js 安装）
- jq（可选，用于自动更新 oh-my-openagent 模型配置）
- gh（可选，GitHub CLI；安装全部组件时脚本会自动按官方方式安装：https://cli.github.com/）

### macOS

#### 核心依赖

| 依赖 | 必要性 | 说明 |
|------|--------|------|
| **Xcode Command Line Tools** | 🔴 安装 Homebrew 时必需 | 提供 `clang` 编译器、`make`、`git` 及系统 SDK 头文件。安装全部组件时会自动检查，选择性安装指定组件（如 `--node --opencode`）则无需。通过 `xcode-select --install` 安装 |
| **Homebrew** | 🟡 安装系统依赖时必需 | macOS 包管理器。安装全部组件时脚本会自动安装 Homebrew；仅安装 npm 包类组件（opencode、openspec、oso）则不需要 |
| **Bash** | 🟢 运行脚本 | macOS 默认 bash 为 **3.2**（2007 年发布，不支持 `pipefail`）。脚本兼容 3.2，推荐通过 `brew install bash` 升级至 bash 4+ |
| **curl** | 🟢 系统工具 | macOS 预装，无需额外安装 |
| **gh** | 🟡 安装系统依赖时自动安装 | GitHub CLI。安装全部组件时若缺失，脚本通过 `brew install gh` 自动安装（官方方式） |
| **jq** | ⚪ 可选（oh-my-openagent 模型配置） | 用于自动更新模型参数。通过 `brew install jq` 安装 |

#### 架构差异

macOS 在 Apple Silicon（M 系列）和 Intel 上的关键区别：

| | Intel Mac | Apple Silicon (M1/M2/M3/M4) |
|--|-----------|---------------------------|
| **Homebrew 前缀** | `/usr/local` | `/opt/homebrew` |
| **npm 全局 bin** | `/usr/local/bin` | `/opt/homebrew/bin` |
| **Shell 配置** | `~/.bash_profile` | `~/.zshrc`（macOS 默认） |
| **Node.js 架构** | x64 | arm64（nvm 自动识别） |

#### 关于 Xcode.app

**不需要安装完整的 Xcode IDE**（12GB+）。脚本仅依赖 Xcode **Command Line Tools**（约 1.6GB），仅提供命令行编译工具。除非你需要开发 iOS/macOS 原生应用，否则无需安装完整 Xcode。

## 使用方法

```
./wininstall.ps1   [操作] [组件...]    # Windows
./linuxinstall.sh    [操作] [组件...]    # Linux
./macinstall.sh [操作] [组件...]    # macOS
```

### 操作

| 操作 | 说明 |
|------|------|
| `install`（默认） | 安装指定组件 |
| `update` | 更新指定组件到最新版本 |
| `uninstall` | 卸载指定组件 |
| `--help` / `-h` | 显示帮助信息 |

### 组件标志

| 标志 | 组件 |
|------|------|
| `--node` | Node.js |
| `--opencode` | opencode |
| `--oh-my-openagent` | oh-my-openagent |
| `--openspec` | openspec |
| `--superpowers` | superpowers |
| `--codegraph` | codegraph（npm 全局包 + opencode MCP 注册） |
| `--oso` | openspec-superpowers-opencode |

## 使用示例

### 安装全部 7 个组件（首次配置）

```powershell
# Windows（以管理员身份运行 PowerShell）
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser   # 首次执行
./wininstall.ps1
```

```bash
# Linux
./linuxinstall.sh

# macOS
./macinstall.sh
```

### 安装指定组件

```bash
# Windows
./wininstall.ps1 install --node --opencode

# Linux
./linuxinstall.sh install --node --opencode

# macOS
./macinstall.sh install --node --opencode
```

### 更新特定组件

```bash
# Windows
./wininstall.ps1 update --openspec --oso

# Linux
./linuxinstall.sh update --openspec --oso

# macOS
./macinstall.sh update --openspec --oso
```

### 卸载

```bash
# 卸载全部
./wininstall.ps1 uninstall
./linuxinstall.sh uninstall
./macinstall.sh uninstall

# 卸载指定组件（卸载顺序与安装相反）
./wininstall.ps1 uninstall --oso --superpowers
./linuxinstall.sh uninstall --oso --superpowers
./macinstall.sh uninstall --oso --superpowers
```

### 查看帮助

```bash
./wininstall.ps1 --help
./linuxinstall.sh --help
./macinstall.sh --help
```

## 脚本自动执行的配置

### oh-my-openagent 模型配置

安装 oh-my-openagent 后，脚本会自动扫描配置文件（`~/.omo/omo.jsonc` 优先，旧版 `oh-my-openagent.jsonc`/`oh-my-opencode.jsonc` 兼容），将所有 agents 和 categories 的模型参数更新为：

```json
{
  "model": "opencode/deepseek-v4-flash-free",
  "variant": "max",
  "fallback_models": [
    {"model": "opencode/big-pickle", "variant": "high"},
    {"model": "opencode/minimax-m2.5-free", "variant": "max"},
    {"model": "opencode/nemotron3-superfree", "variant": "max"}
  ],
  "prompt_append": "所有回复、思考过程、工具调用参数及描述，全部必须使用中文。不允许出现英文回复（代码本身、库名、专有名词除外）。"
}
```

> **Linux / macOS**: 依赖 `jq` 命令。如未安装，脚本会跳过模型配置更新并给出警告。
> **Windows**: 原生 PowerShell 实现，无需额外依赖。

### superpowers 插件注册

安装 superpowers 后，脚本会自动将其注册到 `opencode.json` 的 `plugin` 数组中：

```json
{
  "plugin": [
    "superpowers@git+https://github.com/obra/superpowers.git"
  ]
}
```

### oh-my-openagent 备用注册

`bun x oh-my-openagent install` 执行后，脚本会额外通过 `Add-JsonPlugin` / `json_add_plugin` 确保 oh-my-openagent 已注册到 `opencode.json`。

### opencode 插件缓存清理

脚本按以下规则清理 opencode 插件缓存目录（`~/.cache/opencode/packages/`，Windows 为 `%USERPROFILE%\.cache\opencode\packages\`）：

| 组件 | 安装/更新前 | 卸载后 |
|------|------------|--------|
| **oh-my-openagent** | 删除 `oh-my-openagent*` 缓存，强制拉取最新版本 | 删除 `oh-my-openagent*` 缓存残留 |
| **superpowers** | 删除 `superpowers*` 缓存，强制拉取最新版本 | 删除 `superpowers*` 缓存残留 |
| **opencode** | — | 保留缓存（不删除） |

> 说明：oh-my-openagent 和 superpowers 的实际插件代码缓存在 `~/.cache/opencode/packages/` 下。安装/更新前清理可确保重新拉取最新版本；卸载后清理可彻底移除残留文件。
> opencode 卸载时**不会**删除 `~/.cache/opencode` 缓存目录，以保留插件缓存与用户数据。

## 配置文件路径

| 平台 | opencode 配置 | oh-my-openagent 配置（新版） | oh-my-openagent 配置（旧版兼容） |
|------|---------------|---------------------------|-------------------------------|
| **Windows** | `%USERPROFILE%\.config\opencode\opencode.json` | `%USERPROFILE%\.omo\omo.jsonc` | `%USERPROFILE%\.config\opencode\oh-my-openagent.jsonc` |
| **Linux / macOS** | `~/.config/opencode/opencode.json` | `~/.omo/omo.jsonc` | `~/.config/opencode/oh-my-openagent.jsonc` |

新版 `~/.omo/omo.jsonc` 是 oh-my-openagent 安装器生成的统一配置文件。旧版 `oh-my-openagent.jsonc`/`oh-my-opencode.jsonc` 在安装时会被自动迁移合并到统一文件中。
脚本同时兼容 `.jsonc` 和 `.json` 两种扩展名，扫描顺序：`~/.omo/omo.jsonc` → `~/.omo/omo.json` → 旧版遗留文件。

## 常见问题

### 1. 卸载后命令仍然可用

如果 `opencode`、`openspec` 等命令在卸载后仍可执行，最常见的原因是 **权限不足**：

- **Windows**: 以**管理员身份**运行 PowerShell 再执行卸载
- **Linux / macOS**: 脚本会自动尝试 `sudo npm uninstall -g`，如仍失败请手动执行

### 2. oh-my-openagent 模型配置未更新

- **Linux / macOS**: 确认已安装 `jq`（Linux: `apt install jq` / macOS: `brew install jq`）
- **Windows**: 确认 `oh-my-openagent.jsonc` 或 `oh-my-opencode.jsonc` 文件存在且为有效 JSON

### 3. Windows 上安装 superpowers 后 opencode 不识别

确认 `opencode.json` 在正确路径：
```
%USERPROFILE%\.config\opencode\opencode.json
```

而非 `%APPDATA%\opencode\opencode.json`。

### 4. macOS 上 Homebrew / Xcode CLI Tools 安装失败

**问题：** Homebrew 安装依赖 Xcode Command Line Tools，而 `xcode-select --install` 可能因网络原因弹出下载窗口后卡住。

**解决方法：**
- 从 [Apple Developer 官网](https://developer.apple.com/download/all/) 手动下载 Command Line Tools 安装包
- 或先执行 `softwareupdate --list` 查看可用更新，再通过 `softwareupdate -i "Command Line Tools for Xcode-版本号"` 安装
- 如果仅安装 npm 包类组件（opencode、openspec、oso），可跳过 Homebrew 安装

### 5. macOS 上 npm 全局命令找不到

**问题：** 安装 opencode / openspec 后提示 `command not found`。

**原因：** npm 全局 bin 目录未在 `PATH` 中。

**解决方法：**
- **Apple Silicon Mac**: `export PATH="/opt/homebrew/bin:$PATH"`，并加入 shell 配置文件
- **Intel Mac**: `export PATH="/usr/local/bin:$PATH"`，并加入 shell 配置文件
- 或使用 nvm 管理 Node.js（脚本默认方式），nvm 会自动处理 PATH

### 6. 安装过程中网络中断

脚本不会回滚已完成的安装步骤。重新运行脚本即可跳过已安装的组件继续安装剩余组件。

### 7. pwsh（PowerShell Core）安装失败

oso 组件依赖 pwsh。如 winget 和 MSI 直装均失败：

```
https://github.com/PowerShell/PowerShell/releases
```

手动下载安装后重新运行脚本。

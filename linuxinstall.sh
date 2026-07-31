#!/bin/bash
# =============================================================================
# install.sh — 一体化安装/更新/卸载脚本 (Linux)
# 管理以下 7 个组件:
#   1. node          - JavaScript 运行时
#   2. opencode      - AI 编码助手终端工具
#   3. oh-my-openagent - OpenCode 超能力插件 (OMO Ultimate)
#   4. openspec      - 规范驱动开发框架
#   5. superpowers   - 软件工程方法论技能集
#   6. codegraph     - 代码图 MCP 服务器（opencode 集成）
#   7. openspec-superpowers-opencode (oso) - OpenSpec + Superpowers 桥接工具
#
# 用法:
#   chmod +x install.sh
#   ./install.sh                                            # 安装所有组件
#   ./install.sh install                                    # 同上
#   ./install.sh update                                     # 更新所有组件
#   ./install.sh uninstall                                  # 卸载所有组件
#   ./install.sh install --node --opencode                  # 安装 node 和 opencode
#   ./install.sh update --openspec                          # 更新 openspec
#   ./install.sh uninstall --oso --superpowers              # 卸载 oso 和 superpowers
#
# 组件: --node, --opencode, --oh-my-openagent, --openspec, --superpowers, --codegraph, --oso
# =============================================================================

set -euo pipefail

# ─── 颜色定义 ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ─── 路径常量 ────────────────────────────────────────────────────────────────
OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
OPENCODE_JSON="${OPENCODE_CONFIG_DIR}/opencode.json"
OMO_CONFIG_DIR="${HOME}/.omo"
NVM_DIR="${HOME}/.nvm"
NVM_NODE_VERSION="22"

# 有效组件列表
VALID_COMPONENTS=("node" "opencode" "oh-my-openagent" "openspec" "superpowers" "codegraph" "oso")

# ─── 日志函数 ────────────────────────────────────────────────────────────────
log_info()    { echo -e "${CYAN}[信息]${NC} $1"; }
log_success() { echo -e "${GREEN}[成功]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[警告]${NC} $1"; }
log_error()   { echo -e "${RED}[错误]${NC} $1"; }
log_step()    { echo -e "${MAGENTA}━━━ $1 ━━━${NC}"; }
log_banner()  { echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BOLD}${BLUE}  $1${NC}"; echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ─── 前置检查 ────────────────────────────────────────────────────────────────
check_os() {
    local os
    os="$(uname -s)"
    if [[ "$os" != "Linux" ]]; then
        log_error "此脚本适用于 Linux。检测到当前系统: $os"
        log_error "请使用 install.ps1（Windows）或对应的平台脚本。"
        exit 1
    fi

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        log_info "检测到系统: ${NAME} ${VERSION_ID} (${ID})"
    else
        log_info "检测到系统: Linux ($(uname -m))"
    fi

    if [[ $EUID -eq 0 ]]; then
        log_info "以 root 用户运行"
    fi
}

check_command() {
    command -v "$1" &>/dev/null
}

is_root() {
    [[ $EUID -eq 0 ]]
}

require_sudo() {
    if is_root; then
        return 0
    fi
    if ! sudo -n true 2>/dev/null; then
        log_warn "部分操作需要 sudo 权限"
        sudo -v
    fi
}

# ─── JSON 辅助函数（纯 awk，无外部依赖）─────────────────────────────────────
json_has_plugin() {
    local entry="$1"
    if [[ ! -f "$OPENCODE_JSON" ]]; then
        return 1
    fi
    # 精确匹配（如 "oh-my-openagent"）
    grep -qF "\"$entry\"" "$OPENCODE_JSON" 2>/dev/null && return 0
    # 前缀匹配（如 "oh-my-openagent@latest" 也被视为已安装）
    grep -qE "\"$entry@[^\"]*\"" "$OPENCODE_JSON" 2>/dev/null && return 0
    return 1
}

json_add_plugin() {
    local entry="$1"
    local file="$OPENCODE_JSON"
    mkdir -p "$(dirname "$file")"
    # 处理不存在或空文件
    if [[ ! -f "$file" || ! -s "$file" ]]; then
        printf '{\n  "plugin": []\n}\n' > "$file"
    fi
    if json_has_plugin "$entry"; then
        return 0
    fi
    local tmp
    tmp=$(mktemp)
    # 整文件读取 + 括号匹配，支持单行和多行 plugin 数组
    awk -v e="$entry" '
    { buf = buf $0 "\n" }
    END {
        pos = match(buf, /"plugin"[[:space:]]*:[[:space:]]*\[/)
        if (pos == 0) { printf "%s", buf; exit }
        start = pos + RLENGTH - 1  # [ 的位置
        # 跳过空白判断是否为空数组
        after = start + 1
        while (after <= length(buf) && substr(buf, after, 1) ~ /[[:space:]]/) { after++ }
        if (substr(buf, after, 1) == "]") {
            # 空数组: [] -> ["entry"]
            printf "%s\"%s\"%s", substr(buf, 1, start), e, substr(buf, after)
            exit
        }
        # 非空数组，找到匹配的 ]
        depth = 1; p = start + 1
        while (depth > 0 && p <= length(buf)) {
            c = substr(buf, p, 1)
            if (c == "[") depth++
            if (c == "]") depth--
            p++
        }
        end_br = p - 1
        printf "%s, \"%s\"%s", substr(buf, 1, end_br - 1), e, substr(buf, end_br)
    }
    ' "$file" > "$tmp" && mv "$tmp" "$file"
}

json_remove_plugin() {
    local entry="$1"
    local file="$OPENCODE_JSON"
    [[ ! -f "$file" ]] && return 0
    local tmp
    tmp=$(mktemp)
    awk -v e="$entry" '
    /"plugin":/ {
        gsub("[, \t]*\"" e "\"[, \t]*", "", $0)
        gsub(", \\]", "]", $0)
        gsub("\\[,", "[", $0)
        print; next
    }
    { print }
    ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# ─── opencode 插件缓存清理 ───────────────────────────────────────────────────
# 安装/更新前清理缓存可强制重新拉取最新版本；卸载后清理残留
clean_opencode_package_cache() {
    local pattern="$1"
    local cache_dir="${HOME}/.cache/opencode/packages"
    if [[ -d "$cache_dir" ]]; then
        local f found=0
        for f in "${cache_dir}"/${pattern}*; do
            [[ -e "$f" ]] && { found=1; break; }
        done
        if [[ $found -eq 1 ]]; then
            log_info "清理插件缓存: ${cache_dir}/${pattern}*"
            rm -rf "${cache_dir}"/${pattern}*
        fi
    fi
}

# ─── 有效组件检查 ────────────────────────────────────────────────────────────
validate_components() {
    local invalid=()
    local comp v
    for comp in "$@"; do
        local found=false
        for v in "${VALID_COMPONENTS[@]}"; do
            [[ "$comp" == "$v" ]] && { found=true; break; }
        done
        if ! $found; then
            invalid+=("$comp")
        fi
    done
    if [[ ${#invalid[@]} -gt 0 ]]; then
        log_error "无效的组件名: ${invalid[*]}"
        echo -e "  有效组件: ${VALID_COMPONENTS[*]}"
        exit 1
    fi
}

# ─── 组件分发 ────────────────────────────────────────────────────────────────
run_install() {
    case "$1" in
        node)              install_node ;;
        opencode)          install_opencode ;;
        oh-my-openagent)   install_oh_my_openagent ;;
        openspec)          install_openspec ;;
        superpowers)       install_superpowers ;;
        codegraph)         install_codegraph ;;
        oso)               install_oso ;;
    esac
}

run_uninstall() {
    case "$1" in
        node)              uninstall_node ;;
        opencode)          uninstall_opencode ;;
        oh-my-openagent)   uninstall_oh_my_openagent ;;
        openspec)          uninstall_openspec ;;
        superpowers)       uninstall_superpowers ;;
        codegraph)         uninstall_codegraph ;;
        oso)               uninstall_oso ;;
    esac
}

get_component_label() {
    case "$1" in
        node)              echo "Node.js" ;;
        opencode)          echo "opencode" ;;
        oh-my-openagent)   echo "oh-my-openagent" ;;
        openspec)          echo "openspec" ;;
        superpowers)       echo "superpowers" ;;
        codegraph)         echo "codegraph" ;;
        oso)               echo "openspec-superpowers-opencode (oso)" ;;
    esac
}

# ─── GitHub CLI (gh) ─────────────────────────────────────────────────────────
# 官方安装方式参考: https://cli.github.com/
install_gh() {
    log_info "安装缺失的系统依赖: gh (GitHub CLI)"
    require_sudo
    local px=""
    is_root || px="sudo "

    if command -v apt-get &>/dev/null; then
        # Debian/Ubuntu: 添加官方 apt 仓库
        ${px}mkdir -p -m 755 /etc/apt/keyrings || true
        ${px}curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg || true
        ${px}chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg || true
        ${px}mkdir -p -m 755 /etc/apt/sources.list.d || true
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | ${px}tee /etc/apt/sources.list.d/github-cli.list > /dev/null || true
        ${px}apt-get update -qq || true
        ${px}apt-get install -y -qq gh
    elif command -v dnf &>/dev/null; then
        # Fedora/RHEL: 添加官方 rpm 仓库
        ${px}dnf install -y dnf-plugins-core >/dev/null 2>&1 || true
        ${px}dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo || true
        ${px}dnf install -y gh
    elif command -v yum &>/dev/null; then
        # Amazon Linux / CentOS: 添加官方 rpm 仓库
        if ! check_command yum-config-manager; then
            ${px}yum install -y yum-utils >/dev/null 2>&1 || true
        fi
        ${px}yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo || true
        ${px}yum install -y gh
    elif command -v pacman &>/dev/null; then
        # Arch Linux: 社区包 github-cli
        ${px}pacman -S --noconfirm github-cli
    elif command -v zypper &>/dev/null; then
        # openSUSE/SUSE: 添加官方 rpm 仓库
        ${px}zypper addrepo https://cli.github.com/packages/rpm/gh-cli.repo || true
        ${px}zypper ref || true
        ${px}zypper install -y gh
    else
        log_error "不支持的包管理器。请手动安装 gh: https://cli.github.com/"
        exit 1
    fi

    if check_command gh; then
        log_success "gh 安装完成: $(gh --version 2>/dev/null | head -n1)"
    else
        log_error "gh 安装失败，请手动安装: https://cli.github.com/"
        exit 1
    fi
}

# ─── 系统依赖 ────────────────────────────────────────────────────────────────
install_system_deps() {
    log_step "检查系统依赖..."
    local missing=()
    for cmd in curl git tar; do
        check_command "$cmd" || missing+=("$cmd")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "安装缺失的系统依赖: ${missing[*]}"
        require_sudo
        local px=""
        is_root || px="sudo "

        if command -v apt-get &>/dev/null; then
            ${px}apt-get update -qq && ${px}apt-get install -y -qq "${missing[@]}"
        elif command -v dnf &>/dev/null; then
            ${px}dnf install -y "${missing[@]}"
        elif command -v yum &>/dev/null; then
            ${px}yum install -y "${missing[@]}"
        elif command -v pacman &>/dev/null; then
            ${px}pacman -S --noconfirm "${missing[@]}"
        elif command -v zypper &>/dev/null; then
            ${px}zypper install -y "${missing[@]}"
        else
            log_error "不支持的包管理器。请手动安装: ${missing[*]}"
            exit 1
        fi
    fi

    # GitHub CLI (gh): 各发行版包名/仓库不同，单独处理
    if check_command gh; then
        log_success "gh 已安装: $(gh --version 2>/dev/null | head -n1)"
    else
        install_gh
    fi

    log_success "系统依赖已满足"
}

# ─── 组件 1: Node.js ────────────────────────────────────────────────────────
install_node() {
    log_step "组件: Node.js"
    if check_command node; then
        local ver
        ver=$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)
        log_info "Node.js 已安装: $(node --version)"
        if [[ "$ver" -ge 18 ]]; then
            log_success "Node.js 版本满足要求 (>=18)"
            return 0
        fi
        log_warn "Node.js 版本过低，将升级..."
    fi

    if [[ ! -d "$NVM_DIR" ]]; then
        log_info "正在安装 nvm..."
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
    else
        log_info "nvm 已安装"
    fi

    export NVM_DIR="$HOME/.nvm"
    [[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh"

    log_info "正在安装 Node.js ${NVM_NODE_VERSION} LTS..."
    if ! nvm install "${NVM_NODE_VERSION}" --latest-npm 2>/dev/null; then
        log_warn "nvm 安装失败，尝试系统安装..."
        if is_root && command -v apt-get &>/dev/null; then
            curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
            apt-get install -y nodejs
        else
            log_error "Node.js 安装失败"
            exit 1
        fi
    fi
    nvm alias default "${NVM_NODE_VERSION}" 2>/dev/null || true
    nvm use default 2>/dev/null || true

    if ! check_command node; then
        local np
        np="$(nvm which current 2>/dev/null)" || true
        if [[ -n "$np" ]]; then
            local bd="${HOME}/.local/bin"
            mkdir -p "$bd"
            ln -sf "$(dirname "$np")/node" "${bd}/node"
            ln -sf "$(dirname "$np")/npm" "${bd}/npm"
            ln -sf "$(dirname "$np")/npx" "${bd}/npx"
            export PATH="${bd}:${PATH}"
        fi
    fi

    if check_command node; then
        log_success "Node.js $(node --version) 安装完成"
        log_info "npm 版本: $(npm --version)"
    else
        log_error "Node.js 安装失败"
        exit 1
    fi
}

# ─── 组件 2: opencode ──────────────────────────────────────────────────────
install_opencode() {
    log_step "组件: opencode"
    if check_command opencode; then
        local ver
        ver=$(opencode --version 2>/dev/null || true)
        log_info "opencode 已安装: ${ver:-?}"
        if [[ "${ACTION}" == "update" ]]; then
            log_info "正在更新 opencode..."
            npm install -g opencode-ai@latest
            log_success "opencode 已更新至 $(opencode --version)"
        else
            log_success "opencode 已安装，跳过"
        fi
        return 0
    fi

    log_info "正在安装 opencode..."
    npm install -g opencode-ai@latest
    if check_command opencode; then
        log_success "opencode $(opencode --version) 安装完成"
    else
        log_error "opencode 安装失败"
        exit 1
    fi
}

# ─── 组件 3: oh-my-openagent ───────────────────────────────────────────────
set_oh_my_openagent_model() {
    if ! check_command jq; then
        log_warn "jq 未安装，跳过模型配置更新"
        return 0
    fi

    local model="opencode/deepseek-v4-flash-free"
    local variant="max"
    local fallback='[{"model":"opencode/big-pickle","variant":"high"},{"model":"opencode/minimax-m2.5-free","variant":"max"},{"model":"opencode/nemotron3-superfree","variant":"max"}]'
    local prompt="所有回复、思考过程、工具调用参数及描述，全部必须使用中文。不允许出现英文回复（代码本身、库名、专有名词除外）。"

    for f in \
        "${OMO_CONFIG_DIR}/omo.jsonc" \
        "${OMO_CONFIG_DIR}/omo.json" \
        "${OPENCODE_CONFIG_DIR}/oh-my-openagent.jsonc" \
        "${OPENCODE_CONFIG_DIR}/oh-my-opencode.jsonc" \
        "${OPENCODE_CONFIG_DIR}/oh-my-openagent.json" \
        "${OPENCODE_CONFIG_DIR}/oh-my-opencode.json"; do
        [[ -f "$f" ]] || continue

        if sed '\|^[[:space:]]*//|d' "$f" 2>/dev/null | jq --arg model "$model" --arg variant "$variant" --argjson fallback "$fallback" --arg prompt "$prompt" '
            def _update: with_entries(.value.model = $model | .value.variant = $variant | .value.fallback_models = $fallback | .value.prompt_append = $prompt);
            if .["[opencode]"] then
                .["[opencode]"].agents |= (if . then _update else . end) |
                .["[opencode]"].categories |= (if . then _update else . end)
            else
                .agents |= (if . then _update else . end) |
                .categories |= (if . then _update else . end)
            end
        ' > "${f}.tmp" 2>/dev/null; then
            mv "${f}.tmp" "$f"
            log_info "已更新 $(basename "$f") 模型配置"
        else
            rm -f "${f}.tmp"
            log_warn "跳过 $(basename "$f") 模型配置更新"
        fi
    done
}

install_oh_my_openagent() {
    log_step "组件: oh-my-openagent"

    if ! check_command bun; then
        log_info "正在安装 Bun..."
        curl -fsSL https://bun.sh/install | bash
        export BUN_INSTALL="${HOME}/.bun"
        [[ -d "$BUN_INSTALL" ]] && export PATH="${BUN_INSTALL}/bin:${PATH}"
        if [[ -f "${HOME}/.bashrc" ]] && ! grep -q 'bun' "${HOME}/.bashrc"; then
            echo "export BUN_INSTALL=\"\${HOME}/.bun\"" >> "${HOME}/.bashrc"
            echo 'export PATH="${BUN_INSTALL}/bin:${PATH}"' >> "${HOME}/.bashrc"
        fi
    fi

    if ! check_command bun; then
        log_error "Bun 安装失败"
        exit 1
    fi
    log_info "Bun $(bun --version) 就绪"

    if json_has_plugin "oh-my-openagent"; then
        log_info "oh-my-openagent 已注册"
        if [[ "${ACTION}" == "update" ]]; then
            log_info "正在更新 oh-my-openagent..."
            clean_opencode_package_cache "oh-my-openagent"
            bunx oh-my-openagent install --no-tui --platform=opencode \
                --claude=no --openai=no --gemini=no --copilot=no \
                --opencode-zen=yes --zai-coding-plan=no --opencode-go=no \
                --kimi-for-coding=no --vercel-ai-gateway=no || true
            set_oh_my_openagent_model
            log_success "oh-my-openagent 更新完成"
        else
            log_success "oh-my-openagent 已安装，跳过"
        fi
        return 0
    fi

    log_info "正在安装 oh-my-openagent..."
    mkdir -p "$OPENCODE_CONFIG_DIR"

    clean_opencode_package_cache "oh-my-openagent"
    bunx oh-my-openagent install --no-tui --platform=opencode \
        --claude=no --openai=no --gemini=no --copilot=no \
        --opencode-zen=yes --zai-coding-plan=no --opencode-go=no \
        --kimi-for-coding=no --vercel-ai-gateway=no || {
        log_warn "安装程序遇到问题，直接注册插件..."
        json_add_plugin "oh-my-openagent"
    }

    set_oh_my_openagent_model
    log_success "oh-my-openagent 安装完成"
}

# ─── 组件 4: openspec ──────────────────────────────────────────────────────
install_openspec() {
    log_step "组件: openspec"
    if check_command openspec; then
        local ver
        ver=$(openspec --version 2>/dev/null || true)
        log_info "openspec 已安装: ${ver:-?}"
        if [[ "${ACTION}" == "update" ]]; then
            log_info "正在更新 openspec..."
            npm install -g @fission-ai/openspec@latest
            log_success "openspec 已更新"
        else
            log_success "openspec 已安装，跳过"
        fi
        return 0
    fi

    log_info "正在安装 openspec..."
    npm install -g @fission-ai/openspec@latest
    if check_command openspec; then
        log_success "openspec 安装完成"
    else
        log_error "openspec 安装失败"
        exit 1
    fi
}

# ─── 组件 5: superpowers ──────────────────────────────────────────────────
install_superpowers() {
    log_step "组件: superpowers"
    local entry="superpowers@git+https://github.com/obra/superpowers.git"

    if json_has_plugin "$entry"; then
        log_info "superpowers 已注册"
        if [[ "${ACTION}" == "update" ]]; then
            log_info "正在更新 superpowers..."
            clean_opencode_package_cache "superpowers"
            log_info "缓存已清理，重启 OpenCode 后自动拉取最新版本"
        else
            log_success "superpowers 已安装，跳过"
        fi
        return 0
    fi

    log_info "正在安装 superpowers..."
    clean_opencode_package_cache "superpowers"
    json_add_plugin "$entry"
    log_success "superpowers 安装完成"
    log_info "重启 OpenCode 后生效"
}

# ─── 组件 6: codegraph ────────────────────────────────────────────────────
# 参考: https://github.com/colbymchenry/codegraph
install_codegraph() {
    log_step "组件: codegraph"
    if check_command codegraph; then
        local ver
        ver=$(codegraph --version 2>/dev/null || true)
        log_info "codegraph 已安装: ${ver:-?}"
        if [[ "${ACTION}" == "update" ]]; then
            log_info "正在更新 codegraph..."
            if codegraph upgrade 2>/dev/null; then
                log_success "codegraph 已更新至 $(codegraph --version 2>/dev/null || echo '?')"
            else
                log_warn "codegraph upgrade 失败，回退到 npm 更新..."
                npm install -g @colbymchenry/codegraph@latest
                codegraph install --target opencode --location global -y 2>/dev/null || true
                log_success "codegraph 已通过 npm 更新"
            fi
        else
            log_success "codegraph 已安装，跳过"
        fi
        return 0
    fi

    log_info "正在安装 codegraph..."
    npm install -g @colbymchenry/codegraph
    if ! check_command codegraph; then
        log_error "codegraph 安装失败"
        exit 1
    fi

    log_info "正在注册 codegraph 到 opencode..."
    codegraph install --target opencode --location global -y
    log_success "codegraph 安装完成"
}

# ─── 组件 7: oso ──────────────────────────────────────────────────────────
install_oso() {
    log_step "组件: openspec-superpowers-opencode (oso)"
    if check_command openspec-superpowers-opencode; then
        local ver
        ver=$(openspec-superpowers-opencode --version 2>/dev/null || true)
        log_info "oso 已安装: ${ver:-?}"
        if [[ "${ACTION}" == "update" ]]; then
            log_info "正在更新 oso..."
            npm update -g @moyaspace/openspec-superpowers-opencode
            log_success "oso 已更新"
        else
            log_success "oso 已安装，跳过"
        fi
        return 0
    fi

    log_info "正在安装 oso..."
    npm install -g @moyaspace/openspec-superpowers-opencode
    chmod +x "$(npm prefix -g)/bin/openspec-superpowers-opencode" 2>/dev/null || true
    if check_command openspec-superpowers-opencode; then
        log_success "oso 安装完成"
    else
        log_error "oso 安装失败"
        exit 1
    fi
}

# ─── 卸载 ──────────────────────────────────────────────────────────────────
uninstall_node() {
    log_info "正在卸载 Node.js..."
    if [[ -d "$NVM_DIR" ]]; then
        export NVM_DIR="$HOME/.nvm"
        [[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh"
        nvm deactivate 2>/dev/null || true
        nvm uninstall "${NVM_NODE_VERSION}" 2>/dev/null || true
        log_info "nvm 保留在 ${NVM_DIR}，如需移除请手动删除"
        log_success "Node.js (nvm 版本) 已卸载"
    else
        log_info "未检测到 nvm 管理的 Node.js"
    fi
}

uninstall_opencode() {
    if ! check_command opencode; then
        log_info "opencode 未安装"
        return 0
    fi

    log_info "正在卸载 opencode..."
    if npm uninstall -g opencode-ai 2>/dev/null; then
        sleep 1
        if check_command opencode; then
            log_warn "opencode 仍可执行，尝试: sudo npm uninstall -g opencode-ai"
        else
            log_success "opencode 已卸载"
        fi
    else
        log_warn "npm uninstall 失败，尝试 sudo..."
        if sudo npm uninstall -g opencode-ai 2>/dev/null; then
            log_success "opencode 已卸载 (sudo)"
        else
            log_warn "卸载失败，请手动执行: sudo npm uninstall -g opencode-ai"
        fi
    fi

    # 保留 opencode 缓存目录（含插件缓存与用户数据），不随卸载删除
}

uninstall_oh_my_openagent() {
    log_info "正在卸载 oh-my-openagent..."
    json_remove_plugin "oh-my-openagent"
    rm -f "${OPENCODE_CONFIG_DIR}/oh-my-openagent.jsonc" \
          "${OPENCODE_CONFIG_DIR}/oh-my-opencode.jsonc" \
          "${OPENCODE_CONFIG_DIR}/oh-my-openagent.json" \
          "${OPENCODE_CONFIG_DIR}/oh-my-opencode.json"
    rm -f "${OMO_CONFIG_DIR}/omo.jsonc" "${OMO_CONFIG_DIR}/omo.json"
    rmdir "${OMO_CONFIG_DIR}" 2>/dev/null || true
    clean_opencode_package_cache "oh-my-openagent"
    log_success "oh-my-openagent 已卸载"
}

uninstall_openspec() {
    if ! check_command openspec; then
        log_info "openspec 未安装"
        return 0
    fi
    log_info "正在卸载 openspec..."
    if npm uninstall -g @fission-ai/openspec 2>/dev/null; then
        log_success "openspec 已卸载"
    else
        log_warn "npm uninstall 失败，尝试 sudo..."
        if sudo npm uninstall -g @fission-ai/openspec 2>/dev/null; then
            log_success "openspec 已卸载 (sudo)"
        else
            log_warn "卸载失败，请手动执行: sudo npm uninstall -g @fission-ai/openspec"
        fi
    fi
}

uninstall_superpowers() {
    log_info "正在卸载 superpowers..."
    json_remove_plugin "superpowers"
    rm -rf "${OPENCODE_CONFIG_DIR}/plugins/superpowers" 2>/dev/null || true
    rm -rf "${OPENCODE_CONFIG_DIR}/skills/superpowers" 2>/dev/null || true
    clean_opencode_package_cache "superpowers"
    log_success "superpowers 已卸载"
}

uninstall_codegraph() {
    if ! check_command codegraph; then
        log_info "codegraph 未安装"
        return 0
    fi

    log_info "正在卸载 codegraph..."
    # 先移除 opencode 集成配置（--keep-cli 保留 CLI 以便继续执行）
    codegraph uninstall --target opencode --location global -y --keep-cli 2>/dev/null || true
    # 再卸载 npm 全局包（npm 包的 preuninstall 钩子会自动清理其余 global 配置）
    if npm uninstall -g @colbymchenry/codegraph 2>/dev/null; then
        log_success "codegraph 已卸载"
    else
        log_warn "npm uninstall 失败，尝试 sudo..."
        if sudo npm uninstall -g @colbymchenry/codegraph 2>/dev/null; then
            log_success "codegraph 已卸载 (sudo)"
        else
            log_warn "卸载失败，请手动执行: sudo npm uninstall -g @colbymchenry/codegraph"
        fi
    fi
}

uninstall_oso() {
    if ! check_command openspec-superpowers-opencode; then
        log_info "oso 未安装"
        return 0
    fi
    log_info "正在卸载 openspec-superpowers-opencode..."
    if npm uninstall -g @moyaspace/openspec-superpowers-opencode 2>/dev/null; then
        log_success "oso 已卸载"
    else
        log_warn "npm uninstall 失败，尝试 sudo..."
        if sudo npm uninstall -g @moyaspace/openspec-superpowers-opencode 2>/dev/null; then
            log_success "oso 已卸载 (sudo)"
        else
            log_warn "卸载失败，请手动执行: sudo npm uninstall -g @moyaspace/openspec-superpowers-opencode"
        fi
    fi
}

# ─── 用法 ──────────────────────────────────────────────────────────────────
show_usage() {
    echo -e "${BOLD}用法:${NC} $0 [操作] [--组件名...]"
    echo ""
    echo "  操作 (默认: install):"
    echo "    install   - 安装组件"
    echo "    update    - 更新组件"
    echo "    uninstall - 卸载组件"
    echo ""
    echo "  组件 (默认: 全部 7 个):"
    echo "    --node              Node.js 运行时"
    echo "    --opencode          AI 编码助手"
    echo "    --oh-my-openagent   OpenCode 超能力插件"
    echo "    --openspec          规范驱动开发框架"
    echo "    --superpowers       软件工程方法论"
    echo "    --codegraph         代码图 MCP 服务器"
    echo "    --oso               OpenSpec+Superpowers 桥接工具"
    echo ""
    echo "  示例:"
    echo "    $0                                    # 安装所有组件"
    echo "    $0 install --node --opencode          # 安装 node 和 opencode"
    echo "    $0 update --openspec                  # 仅更新 openspec"
    echo "    $0 uninstall --oso                    # 卸载 oso"
    echo "    $0 --node                             # 安装 (默认) node"
    echo "    $0 uninstall                          # 卸载所有组件"
}

# ─── 主函数 ────────────────────────────────────────────────────────────────
main() {
    clear

    local ACTION=""
    local COMPONENTS=()
    local seen_action=false

    for arg in "$@"; do
        case "$arg" in
            --help|-h|help)
                show_usage
                exit 0
                ;;
            --*)
                local comp_name="${arg#--}"
                COMPONENTS+=("$comp_name")
                ;;
            install|update|uninstall)
                if [[ "$seen_action" == false ]]; then
                    ACTION="$arg"
                    seen_action=true
                else
                    log_error "重复的操作参数: $arg"
                    exit 1
                fi
                ;;
            *)
                log_error "未知参数: $arg"
                show_usage
                exit 1
                ;;
        esac
    done

    [[ -z "$ACTION" ]] && ACTION="install"

    if [[ ${#COMPONENTS[@]} -eq 0 ]]; then
        COMPONENTS=("${VALID_COMPONENTS[@]}")
    fi

    validate_components "${COMPONENTS[@]}"
    check_os

    if [[ "$ACTION" == "uninstall" ]]; then
        if [[ ${#COMPONENTS[@]} -eq ${#VALID_COMPONENTS[@]} ]]; then
            log_banner "开始卸载所有组件"
        else
            local labels=()
            local c
            for c in "${COMPONENTS[@]}"; do
                labels+=("$(get_component_label "$c")")
            done
            log_banner "开始卸载组件: ${labels[*]}"
        fi
        local reversed=()
        for ((i=${#COMPONENTS[@]}-1; i>=0; i--)); do
            reversed+=("${COMPONENTS[$i]}")
        done
        for c in "${reversed[@]}"; do
            run_uninstall "$c"
        done
        log_banner "指定组件卸载完成！"
        return 0
    fi

    local action_label
    [[ "$ACTION" == "update" ]] && action_label="更新" || action_label="安装"

    if [[ ${#COMPONENTS[@]} -eq ${#VALID_COMPONENTS[@]} ]]; then
        log_banner "开始${action_label}全部 7 个组件"
    else
        local labels=()
        local c
        for c in "${COMPONENTS[@]}"; do
            labels+=("$(get_component_label "$c")")
        done
        log_banner "开始${action_label}组件: ${labels[*]}"
    fi

    echo ""
    log_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    if [[ ${#COMPONENTS[@]} -eq ${#VALID_COMPONENTS[@]} ]]; then
        install_system_deps
    fi

    for c in "${COMPONENTS[@]}"; do
        run_install "$c"
    done

    # opencode 初始化并测试（仅含 superpowers 或 oso 时）
    if [[ " ${COMPONENTS[*]} " =~ " superpowers " || " ${COMPONENTS[*]} " =~ " oso " ]]; then
        if check_command opencode; then
            log_info "opencode初始化并测试"
            opencode run "hello" --model opencode/deepseek-v4-flash-free 2>/dev/null || true
        fi
    fi

    echo ""
    log_banner "指定组件${action_label}完成！"
    echo ""
    echo -e "  ${GREEN}✓${NC} 运行命令 'opencode run \"hello\" --model opencode/deepseek-v4-flash-free' 测试 opencode"
    echo -e "  ${GREEN}✓${NC} 在项目目录运行 'openspec-superpowers-opencode init' 初始化 oso"
    echo ""
    log_info "完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
}

main "$@"

#!/bin/bash

# AI CLI 工具系统提示词链接脚本
# 将 AGENTS.md 链接到各个 CLI 工具的配置目录中作为系统提示词

set -e

# 源文件路径（脚本所在目录下的 AGENTS.md）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="$SCRIPT_DIR/AGENTS.md"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "========================================="
echo "AI CLI 工具系统提示词链接脚本"
echo "========================================="
echo ""

# 检查源文件是否存在
if [ ! -f "$SOURCE_FILE" ]; then
    echo -e "${RED}错误: 源文件 $SOURCE_FILE 不存在${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 找到源文件: $SOURCE_FILE${NC}"
echo ""

# 函数: 创建符号链接
# 参数: $1 = CLI 工具名称, $2 = 目标目录, $3 = 目标文件名
create_symlink() {
    local tool_name="$1"
    local target_dir="$2"
    local target_filename="$3"
    local target_file="$target_dir/$target_filename"
    
    echo "处理 $tool_name..."
    
    # 检查 CLI 工具是否安装
    if ! command -v "$tool_name" &> /dev/null; then
        echo -e "${YELLOW}  ⚠ $tool_name 未安装，跳过${NC}"
        return
    fi
    
    echo -e "${GREEN}  ✓ $tool_name 已安装${NC}"
    
    # 创建目标目录（如果不存在）
    if [ ! -d "$target_dir" ]; then
        echo "  → 创建目录: $target_dir"
        mkdir -p "$target_dir"
    fi
    
    # 检查目标文件是否已存在
    if [ -e "$target_file" ] || [ -L "$target_file" ]; then
        # 检查是否已经是正确的符号链接
        if [ -L "$target_file" ] && [ "$(readlink -f "$target_file")" = "$(readlink -f "$SOURCE_FILE")" ]; then
            echo -e "${GREEN}  ✓ 符号链接已存在且正确: $target_file${NC}"
            return
        else
            echo -e "${YELLOW}  ⚠ 目标文件已存在: $target_file${NC}"
            echo "  → 备份现有文件..."
            mv "$target_file" "$target_file.backup.$(date +%Y%m%d_%H%M%S)"
        fi
    fi
    
    # 创建符号链接
    echo "  → 创建符号链接: $target_file -> $SOURCE_FILE"
    ln -s "$SOURCE_FILE" "$target_file"
    echo -e "${GREEN}  ✓ 成功创建符号链接${NC}"
}

# 为 Codex 创建链接
# Codex 使用 ~/.codex/instructions.md 作为全局指令文件
create_symlink "codex" "$HOME/.codex" "AGENTS.md"

# 为 Claude 创建链接
# Claude 可以使用 CLAUDE.md 或通过 --system-prompt-file 指定
create_symlink "claude" "$HOME/.claude" "CLAUDE.md"

# 为 Gemini 创建链接
# Gemini 配置目录
create_symlink "gemini" "$HOME/.gemini" "GEMINI.md"

echo ""
echo "========================================="
echo -e "${GREEN}完成!${NC}"
echo "========================================="
echo ""
echo "使用说明:"
echo "  • Codex: 会自动加载 ~/.codex/AGENTS.md"
echo "  • Claude: 使用 'claude --system-prompt-file ~/.claude/CLAUDE.md' 或在项目中使用 CLAUDE.md"
echo "  • Gemini: 配置文件位于 ~/.gemini/GEMINI.md"
echo ""

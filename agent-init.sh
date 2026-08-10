#!/bin/bash

# AI CLI 工具及项目系统提示词和技能同步初始化脚本
set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 配置列表: 格式为 "tool_name|target_dir|target_filename"
AGENTS_CONFIG=(
  "codex|$HOME/.codex|AGENTS.md"
  "claude|$HOME/.claude|CLAUDE.md"
  "gemini|$HOME/.gemini|GEMINI.md"
  "qoder|$HOME/.qoder|AGENTS.md"
)

# 源目录路径（脚本所在目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE_AGENTS="$SCRIPT_DIR/AGENTS.md"
SOURCE_SKILLS_DIR="$SCRIPT_DIR/skills"

echo "AI Agent 系统提示词与技能同步初始化工具"
echo ""

# 检查源文件是否存在
if [ ! -f "$SOURCE_FILE_AGENTS" ]; then
    echo -e "${RED}错误: 源提示词文件 $SOURCE_FILE_AGENTS 不存在${NC}"
    exit 1
fi

# 函数: 安全地创建或更新符号链接 (通用于文件或目录)
# 参数: $1 = 源路径, $2 = 目标路径
create_symlink() {
    local source_path="$1"
    local target_path="$2"
    local target_dir="$(dirname "$target_path")"
    
    mkdir -p "$target_dir"
    
    if [ -e "$target_path" ] || [ -L "$target_path" ]; then
        # 如果已经是正确的符号链接，跳过
        if [ -L "$target_path" ] && [ "$(readlink -f "$target_path")" = "$(readlink -f "$source_path")" ]; then
            return
        fi
        echo -e "${YELLOW}  ⚠ 目标已存在: $target_path${NC}"
        echo "  → 备份现有文件/目录..."
        mv "$target_path" "$target_path.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    ln -s "$source_path" "$target_path"
    echo -e "${GREEN}  ✓ 成功创建符号链接: $target_path -> $source_path${NC}"
}

# 函数: 同步技能目录并执行清理
# 参数: $1 = 目标技能目录
sync_skills() {
    local target_skills_dir="$1"
    
    if [ ! -d "$SOURCE_SKILLS_DIR" ]; then
        echo -e "${YELLOW}  ⚠ 源技能目录 $SOURCE_SKILLS_DIR 不存在，跳过技能同步${NC}"
        return
    fi
    
    mkdir -p "$target_skills_dir"
    
    # 1. 遍历源技能目录，创建或更新符号链接
    for skill_path in "$SOURCE_SKILLS_DIR"/*; do
        [ -d "$skill_path" ] || continue
        create_symlink "$skill_path" "$target_skills_dir/$(basename "$skill_path")"
    done
    
    # 2. 清理已被删除的远端失效技能链接
    for item in "$target_skills_dir"/*; do
        [ -L "$item" ] || continue
        local link_target
        link_target=$(readlink -f "$item" 2>/dev/null || true)
        
        # 如果软链接指向我们的源技能仓库，但源技能已不存，则进行清理
        if [[ "$link_target" == "$SOURCE_SKILLS_DIR"/* ]] && [ ! -e "$link_target" ]; then
            echo -e "${YELLOW}  → 检测到已失效的源技能，清理链接: $(basename "$item")${NC}"
            rm -f "$item"
        fi
    done
}

# 函数: 初始化并同步全局 Agent 提示词配置
# 参数: $1 = 工具命令名称, $2 = 配置根目录, $3 = 主提示词文件名
init_agent() {
    local tool_name="$1"
    local target_dir="$2"
    local target_filename="$3"
    
    echo "初始化 Agent $tool_name..."
    
    # 1. 链接主提示词文件
    create_symlink "$SOURCE_FILE_AGENTS" "$target_dir/$target_filename"

    # 2. 同步技能目录
    sync_skills "$target_dir/skills"
    
    echo -e "${GREEN}  ✓ $tool_name 初始化/同步完成${NC}"
    echo ""
}

# ============================================================================
# 参数处理与主入口
# ============================================================================

# 遍历配置列表，判断目录是否存在，存在才初始化
for config in "${AGENTS_CONFIG[@]}"; do
    IFS='|' read -r name dir file <<< "$config"
    if [ -d "$dir" ]; then
        init_agent "$name" "$dir" "$file"
    else
        echo -e "${YELLOW}  ⚠ $name 未安装且无配置目录 $dir，跳过${NC}"
        echo ""
    fi
done

echo -e "${GREEN}完成! 所有全局配置已同步并清理失效技能。${NC}"
echo ""

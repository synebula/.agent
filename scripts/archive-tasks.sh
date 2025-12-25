#!/bin/bash

# TASK 文档归档脚本
# 用途：定期归档超过 30 天的 TASK 文档，保持项目根目录整洁

set -e

AGENT_DIR=".agent"
ARCHIVE_DIR="$AGENT_DIR/archive"
DAYS_OLD=30

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo "TASK 文档归档工具"
echo "========================================"
echo ""

# 检查 .agent 目录是否存在
if [ ! -d "$AGENT_DIR" ]; then
    echo "错误: $AGENT_DIR 目录不存在"
    exit 1
fi

# 统计需要归档的文件
count=$(find "$AGENT_DIR" -maxdepth 1 -name "TASK-*.md" -mtime +${DAYS_OLD} 2>/dev/null | wc -l)

if [ "$count" -eq 0 ]; then
    echo -e "${GREEN}✓ 无需归档的 TASK 文档${NC}"
    echo "  所有 TASK 文档都在 ${DAYS_OLD} 天以内"
    exit 0
fi

echo "发现 $count 个超过 ${DAYS_OLD} 天的 TASK 文档"
echo ""

# 列出将被归档的文件
echo "将归档以下文件："
find "$AGENT_DIR" -maxdepth 1 -name "TASK-*.md" -mtime +${DAYS_OLD} | while read file; do
    filename=$(basename "$file")
    file_date=$(date -r "$file" +%Y-%m-%d)
    echo "  - $filename (最后修改: $file_date)"
done
echo ""

# 询问确认
read -p "是否继续归档？(y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

echo ""
echo "开始归档..."
echo ""

# 归档计数器
archived=0

# 执行归档
find "$AGENT_DIR" -maxdepth 1 -name "TASK-*.md" -mtime +${DAYS_OLD} | while read file; do
    # 提取年月
    year_month=$(date -r "$file" +%Y-%m)
    
    # 创建归档目录
    mkdir -p "$ARCHIVE_DIR/$year_month"
    
    # 移动文件
    filename=$(basename "$file")
    echo "  ✓ $filename → archive/$year_month/"
    mv "$file" "$ARCHIVE_DIR/$year_month/"
    
    archived=$((archived + 1))
done

echo ""
echo "========================================"
echo -e "${GREEN}归档完成！${NC}"
echo "========================================"
echo ""
echo "提示："
echo "  • 归档位置: $ARCHIVE_DIR/"
echo "  • 如需查看归档文件: ls -R $ARCHIVE_DIR/"
echo "  • CHANGELOG.md 中的引用路径可能需要更新"
echo ""

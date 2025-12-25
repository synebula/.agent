# 项目记忆（用户环境）

## 概览
- 主要 Shell：zsh + oh-my-zsh
- 主题：powerlevel10k

## zsh 插件与补全
- oh-my-zsh 插件在 `~/.zshrc` 的 `plugins=(...)` 中配置
- 已启用：`docker`、`docker-compose`
- 预生成 docker 补全脚本：`~/.oh-my-zsh/cache/completions/_docker`

## 变更记录
- 2025-12-22：在 `~/.zshrc` 启用 `docker`/`docker-compose` 插件；生成 docker zsh completion 缓存

## 验证步骤
- 重新加载配置：`source ~/.zshrc`
- 检查别名：`alias dps`、`alias dco`
- 检查补全：`autoload -Uz compinit; compinit -i; whence -w _docker _docker-compose`

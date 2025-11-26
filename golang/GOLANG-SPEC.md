# Golang 项目开发规范（基于 gochen 框架）

> 适用范围：基于 gochen 基础设施（eventing/httpx/messaging/di/logging 等）的中型业务项目。
>
> 目标：为 AI 代理或新人提供“能直接落地”的约束与模板，保证代码架构一致、可维护、可验证。

---

## 1. 核心原则

1. **领域优先**：业务以领域为单位纵向切分，先明确聚合/上下文，再考虑技术细节。
2. **读写分离**：命令（写）与查询（读）在结构上解耦，优先用 QueryModel/Projection 表满足查询性能。
3. **渐进复杂度**：除非存在跨节点一致性等硬需求，避免直接上 Event Sourcing/Workflow/插件系统等重型方案。
4. **最小可行框架**：优先复用 gochen 已有能力（DI、路由、事件、日志、调度、Outbox 等），禁止重复造轮子。
5. **安全与可观测性**：默认开启结构化日志、审计、限流、权限检查；所有接口遵循最小权限原则。

---

## 2. 目录与分层约定

```
cmd/                # 每个可执行程序（server/migrate/worker）一个目录
internal/
  app/             # 框架层装配：配置、Router、DI、Schedulers、Outbox
  <domain>/        # 领域模块：entity → repo → service → router → module.go
shared/             # 可跨项目复用的库（gochen 子模块或轻量工具）
configs/            # 环境配置模板（若存在）
docs/               # 需求、设计、运维、规范文档
scripts/            # 集成测试 / 维护脚本
.agent/             # 项目记忆体系
```

- **cmd/** 只负责装配与进程控制，其余逻辑全部落到 internal 包。
- **internal/app** 是唯一的“框架层”入口，内含：
  - `config/`：配置加载与校验；
  - `registry/`：DI 注册、模块提供者；
  - `router/`：HTTP 路由聚合、全局中间件；
  - `middleware/`：认证、日志、限流、追踪等。
- **领域目录模板**（以 progress 为例）：
  - `entity/`：聚合根与值对象（禁止引用 HTTP/DB）；
  - `repo/`：持久化接口 + GORM 实现；
  - `service/`：领域服务、应用服务；
  - `router/`：只做 IRouteRegistrar 实现；
  - `module.go`：实现 `internal/di.IDomainModule`，在此注册 provider/handler/projection。
  - `.agent/CONTEXT.md`：记录域边界、接口契约、变更历史。

---

## 3. gochen 框架使用建议

1. **DI / Registry**：统一通过 `internal/app/registry` 暴露的 Registry 进行依赖注册，遵循“类型字符串 = 服务名”的约定。
2. **HTTP 层**：使用 gochen `httpx` + `internal/server/gin` 适配层；公共中间件（认证/日志/限流/CORS）放在 `internal/app/middleware`。
3. **事件系统**：默认依赖 gochen `eventing`；
   - 普通业务可使用 DomainEvent + Handler + Projection 即可；
   - Event Sourcing 仅在聚合需要长生命周期回放时启用，且需评估存储/监控成本。
4. **消息/Outbox**：跨系统集成场景优先启用 Outbox + Transport，避免直接在领域服务里调用外部 API。
5. **配置与日志**：使用 `internal/app/config` 读取 `.env`/YAML，日志统一通过 `gochen/logging`。
6. **计划任务**：借助 gochen Scheduler（如 PlanScheduler）或 cron worker，不要在 HTTP Handler 内执行长任务。

---

## 4. 领域建模规范

- **上下文边界**：每个领域目录对外仅暴露 `module.go` 中声明的接口；禁止相互直接 import service/repo。
- **聚合设计**：
  - 保持每个聚合的写模型简单（不超过 3 个主值对象）；
  - 通过事件或 ApplicationService 与其他聚合交互；
  - 只在确有必要时使用 Event Sourcing，且提供 Snapshot/Projection 复用。
- **读模型**：
  - 使用 Projection 或 Materialized View 支撑前端查询，避免对写模型直接暴露。
  - Projection 的生命周期由 `internal/app.Application` 统一管理。
- **模块注册**：
  - `RegisterProviders` 用于依赖注入；
  - `RegisterEventHandlers` 订阅事件；
  - `RegisterProjections` 返回 `projectionManager`。

---

## 5. 数据访问与迁移

1. **GORM 规范**：
   - 仓储层只暴露接口，返回 domain entity 或读模型；
   - 所有查询参数通过结构体或 Specification，避免 SQL 拼接。
2. **数据库迁移**：
   - 统一落在 `migrations/{driver}`，采用时间序列命名；
   - CMD `migrate`/`automigrate` 程序负责执行；
   - 禁止在生产二进制自动 `AutoMigrate`。
3. **事务与一致性**：
   - Domain Service 内通过 `repo.WithTransaction` 注入事务上下文；
   - 修改 + 事件发布场景优先用 Outbox 或事务消息。

---

## 6. 编码与错误处理

- **语言特性**：坚持 Go 1.21+，禁止使用实验性语言特性。
- **命名规范**：
  - 包名简短（app/router/progress 等）；
  - 变量名语义化，避免 `tmp`, `foo`。
- **错误处理**：
  - 使用 `shared/errors` 定义错误码并 wrap 原始错误；
  - HTTP 层统一映射到标准响应结构。
- **日志**：
  - 所有日志通过 `logging.Logger` 打；
  - 打印结构化字段（component/domain/userID）。
- **配置**：
  - 配置结构写在 `internal/app/config/config.go`；
  - 所有敏感配置通过环境变量注入，禁止硬编码。
- **安全**：
  - HTTP Handler 必须通过中间件或业务逻辑校验权限；
  - 输入校验与防注入放在 service 层或 router 层的请求 DTO。

---

## 7. 测试与验证

1. **单元测试**：领域服务/仓储关键逻辑必须配测试，命名 `*_test.go`，位于同目录。
2. **集成测试**：跨模块流程（如 progress task）放在 `internal/<domain>/service/..._integration_test.go`。
3. **脚本验证**：
   - `scripts/test_api.sh` 负责端到端 smoke；
   - 所有脚本在结束时必须清理进程（trap）。
4. **CI 检查**：至少运行 `go fmt ./...`、`go vet ./...`、`go test ./...`、`golangci-lint run`（如已配置）。

---

## 8. 文档与项目记忆

- **多层级 CONTEXT**：
  - 根 `.agent/CONTEXT.md` 记录全局决策；
  - 每个目录维护自己的 `.agent/CONTEXT.md`；
  - 新任务需创建 `.agent/TASK-*.md`，完成后更新相关 CONTEXT。
- **设计文档**：
  - 所有重要改动在 `docs/` 下创建主题文档，结构包含：背景、目标、方案、风险、验收。
  - 与特定模块强相关的文档放在 `docs/internal/<domain>-<topic>.md`。
- **知识传递**：提交 PR 前附带“影响面 + 验证方式 + 回滚方案”。

---

## 9. 运维与可观测性

1. **启动方式**：统一 `go run cmd/server/main.go` 或构建后的 `./bin/server`；server 负责注册优雅关闭（SIGINT/SIGTERM）。
2. **健康检查**：暴露 `/health` 与 `/api/v1/monitoring/health`；监控脚本使用 HTTP 200 判定。
3. **指标**：
   - 事件/投影/Outbox 提供基础指标（pending/failed count）；
   - Scheduler 暴露最后运行时间；
   - 关键业务可通过日志 + APM 上报。
4. **配置管理**：
   - 环境变量通过 `.env` 注入，生产使用 secrets manager；
   - 配置变动需更新文档与 CONTEXT。

---

## 10. 决策清单（给 AI 的快速检查）

- [ ] 是否复用 gochen 提供的 DI/Router/事件等能力？
- [ ] 是否避免不必要的 Event Sourcing / CQRS 复杂度？
- [ ] 是否按领域划分目录并提供 `.agent/CONTEXT.md`？
- [ ] 是否所有跨域依赖都通过事件/API/模块接口？
- [ ] 是否提供测试与验证步骤？
- [ ] 是否更新相关文档与项目记忆？
- [ ] 是否有清晰的回滚方案？
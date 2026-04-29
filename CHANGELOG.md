# 更新日志

## 未发布

- 修复启动时已有本地 SQLite 数据会跳过 Keychain 管理密钥恢复的问题；刷新/导入写入 SQLite 和快照重建改到后台 utility 任务，减少设置页测试连接与刷新时的主线程卡顿。
- 自动刷新默认间隔调整为 60 秒，最小间隔调整为 10 秒；SQLite 启用 WAL、busy_timeout=3000、synchronous=NORMAL，并限制 raw_fetches 仅保留最新 200 条且为 fetched_at 建立索引。
- 新增明文 SQLite 使用历史库（Application Support/cpa-usage-watcher/usage.sqlite3），刷新/导入后可持久化请求事件（usage_events upsert）、原始响应（raw_fetches 明文 JSON）与凭证额度快照（credential_quota_snapshots），并支持离线聚合仪表盘数据；状态码类导入响应无事件时也会持久化上传载荷。
- ViewModel 在启动、刷新、导入和时间范围切换时均优先从 SQLite 读取；SQLite 查询成功（包括空结果）时不回退到 rawPayload；启动 SQLite 读取错误会显示在 errorMessage 而非静默忽略。
- 新增 10–3600 秒自动刷新设置，设置页可控制启用状态和刷新间隔；刷新循环可取消、不重叠（isLoading 守卫），设置通过 UsagePreferencesStore 持久化。
- 重构仪表盘表格为横向可滚动的宽列布局（RequestEvents 942pt、ModelStats 860pt、EndpointStats 700pt），减少列宽挤压；新增 provider-neutral 凭证额度卡片，额度数据来源于聚合器生成的 CredentialQuotaSnapshot，API 凭证（sk- 前缀/API endpoint 类型）不展示额度卡。
- 优化趋势图为线性走势（无平滑）并加入 stock 式 hover crosshair/tooltip，tooltip 显示原始请求数/token/成本；服务健康改为最近 7 天、10 分钟粒度共 1008 格（168 列 × 6 行）热力图，单元格颜色由 HealthBucketStatus（ok/warning/degraded/failed/empty）驱动。
- 新增用于监控 CPA 使用统计的 SwiftUI macOS 仪表盘，支持连接 `/v0/management/usage`，管理密钥通过 Keychain 保存。
- 新增独立表格组件、导入/导出流程、可配置价格设置，以及使用统计仪表盘的行为检查。
- 验证说明：当前 `xcode-select` 指向 CommandLineTools 而不是完整 Xcode，因此暂时无法完成完整 `xcodebuild` 验证和应用截图采集。

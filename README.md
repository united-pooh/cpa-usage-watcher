# CPA Usage Watcher

CPA Usage Watcher 是一个为了制作监控 CPA 统计数据的 mac 桌面小组件而诞生的桌面项目，使用 SwiftUI 构建。

## 功能特性

- 连接可配置的 CPA 管理接口。
- 展示使用概览、趋势图、服务健康状态、接口统计、模型统计、凭证统计和请求事件。
- 支持使用数据导入与导出。
- 支持以 USD 和 CNY 展示成本，并可配置计费参数。

## 运行要求

- macOS
- Xcode
- 支持 SwiftUI 的 macOS target

## 快速开始

1. 使用 Xcode 打开 `cpa-usage-watcher.xcodeproj`。
2. 选择 `cpa-usage-watcher` scheme。
3. 构建并运行应用。
4. 在应用内打开连接设置，填写管理接口地址和管理密钥。

## 项目结构

- `cpa-usage-watcher/Models`：使用数据模型和展示配置。
- `cpa-usage-watcher/Services`：API 客户端、数据聚合、偏好设置和导出服务。
- `cpa-usage-watcher/ViewModels`：仪表盘状态管理。
- `cpa-usage-watcher/Views`：SwiftUI 仪表盘、表格、指标、图表和设置界面。
- `cpa-usage-watcherTests`：测试 target。

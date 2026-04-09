# LookinMCP 使用说明

## 这是什么

`LookinMCP` 是这个仓库里新增的一个原生 macOS 命令行 MCP 服务。

它复用了 Lookin 已有的连接和层级抓取能力，但不启动 Lookin 主窗口，直接通过 `stdio` 和支持 MCP 的客户端通信，比如 Codex。

当前这版是只读能力，主要给 agent 做 UI 检查：

- 扫描可检查的 app
- 连接模拟器或 USB 真机上的 app
- 拉取层级树
- 搜索节点
- 拉取节点 detail
- 导出单个节点截图

## 前置条件

在开始前，需要满足这几件事：

1. 被检查的 iOS app 已经集成 `LookinServer`，并且是 Debug 可用状态。
2. 目标 app 正在运行。
3. 如果看模拟器，模拟器里的 app 要已经启动。
4. 如果看真机，设备需要通过 USB 连上当前 Mac。

如果 `list_apps` 返回空数组，通常先从这几项排查。

## 构建

推荐把构建产物固定到仓库里的 `Build` 目录，这样 Codex 配置里可以直接写稳定路径。

在仓库根目录执行：

```sh
pod install
xcodebuild \
  -workspace Lookin.xcworkspace \
  -scheme LookinMCP \
  -configuration Debug \
  build \
  CODE_SIGNING_ALLOWED=NO \
  BUILD_DIR="$PWD/Build"
```

构建完成后，主要会有这几个路径：

- 可执行文件：`/Users/arthur/github/Lookin/Build/Debug/LookinMCP`
- 运行期依赖：`/Users/arthur/github/Lookin/Build/Frameworks`

这里有个要点：`LookinMCP` 运行时会从兄弟目录 `Build/Frameworks` 读取依赖，所以不要只拿走单个二进制文件。

## 本地手动验证

先确认进程能启动：

```sh
./Build/Debug/LookinMCP
```

它会进入等待 `stdin` 输入的状态，这属于正常表现。

如果想做一个最小握手测试，可以在仓库根目录执行：

```sh
payload='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
printf 'Content-Length: %d\r\n\r\n%s' ${#payload} "$payload" | ./Build/Debug/LookinMCP
```

如果返回 `protocolVersion`、`serverInfo` 这些字段，就说明 MCP 通路已经通了。

## 接到 Codex

Codex 本机配置文件路径是：

`~/.codex/config.toml`

在里面加一个 MCP server，示例：

```toml
[mcp_servers.lookin]
command = "/Users/arthur/github/Lookin/Build/Debug/LookinMCP"
```

如果你还没有用固定 `Build` 目录，也可以填 Xcode 的 DerivedData 产物路径，但那条路径通常不稳定，不太适合长期配置。

改完配置后，重新打开 Codex 会话，或者重启 Codex 客户端，让它重新加载 MCP 配置。

## 在 Codex 里的典型使用方式

建议按这个顺序用：

1. `list_apps`
2. `connect_app`
3. `get_hierarchy`
4. `find_nodes`
5. `get_node_detail`
6. `get_node_screenshot`

一个常见流程是：

1. 先让 agent 调 `list_apps` 找到目标 app。
2. 用 `connect_app` 连上目标。
3. 调 `get_hierarchy` 拿一份完整 snapshot。
4. agent 根据类名、标题、frame、层级关系做分析。
5. 如果某个节点需要进一步确认，再调 `get_node_detail` 或 `get_node_screenshot`。

## 工具说明

### `list_apps`

返回当前可以被 Lookin 检查到的 app 列表。

主要字段：

- `app_ref`
- `bundle_id`
- `app_name`
- `device_type`
- `device_name`
- `os_description`
- `is_usb`
- `is_simulator`
- `server_version_status`

`app_ref` 的格式是：

`bundle_id|device_name|appInfoIdentifier`

当同一个 bundle 同时出现在多个设备上时，后续连接建议直接用 `app_ref`。

### `connect_app`

输入 `app_ref` 或 `bundle_id`。

规则：

- 优先精确匹配 `app_ref`
- 否则按 `bundle_id` 精确匹配
- 0 个命中会报错
- 多个命中会返回候选列表，不会切换当前会话

### `session_status`

返回当前会话状态和 snapshot 元信息。

状态值固定是：

- `disconnected`
- `connecting`
- `connected`
- `reconnecting`

### `disconnect_app`

断开当前会话，并清掉内存里的 snapshot 和临时截图。

### `get_hierarchy`

发起一次新的 hierarchy 请求，并生成新的 `snapshot_id`。

这一步很重要，因为后续查询都基于当前 snapshot。

返回里会有：

- `tree`
- `nodes_by_id`
- `snapshot_id`
- `last_refresh_at`

### `find_nodes`

只查询当前 snapshot，不会偷偷刷新整棵树。

支持参数：

- `query`
- `class_name`
- `visible_only`
- `limit`

匹配范围包括：

- title
- subtitle
- class name
- class chain
- memory address

### `get_node_detail`

按 `node_id` 拉单个节点 detail。

默认返回：

- 规范化后的 node
- 属性列表 `attributes`

可选参数：

- `include_raw`

如果 `include_raw = true`，会额外带一份可 JSON 化的原始摘要。

### `get_node_screenshot`

按 `node_id` 导出节点截图。

支持的 `kind`：

- `appropriate`
- `group`
- `solo`

默认是 `appropriate`。

截图会写到：

`/tmp/lookin-mcp/<session-id>/`

返回里会给你：

- 本地绝对路径
- point 尺寸
- pixel 尺寸
- scale
- 当前截图状态

## Snapshot 和 node id 的规则

`get_hierarchy` 每执行一次，都会生成新的 `snapshot_id`。

下面这几种情况，旧的 `snapshot_id` 和 `node_id` 都应该视为失效：

- 目标 app 重启
- 会话断开后自动重连
- 再次执行 `get_hierarchy`

遇到这类情况，正确做法是重新调一次 `get_hierarchy`。

## 截图规则

`LookinMCP` 不会把图片内联进 MCP 返回体里。

它只返回本地文件路径，这样 agent 后续可以继续基于该文件做分析。

如果截图不可用，返回里会带 `unavailable_reason`。常见原因包括：

- 节点太大
- 当前配置不允许抓图
- 节点没有 preview
- detail 还没拉到

## 常见问题

### 1. `list_apps` 返回 0

优先检查：

- 目标 app 是否真的启动了
- 是否集成了 `LookinServer`
- 是否是 Debug 环境
- 模拟器里的 app 是否处于可响应状态
- 真机是否通过 USB 连上当前 Mac

### 2. `get_node_detail` 报 snapshot 无效

先重新调一次 `get_hierarchy`。

### 3. `get_node_screenshot` 拿不到图片

先看返回里的 `screenshot_status` 和 `unavailable_reason`。

如果节点本身允许截图，通常再调一次 detail 或重新抓一份 hierarchy 就能继续排查。

### 4. 启动时看到 `Lookin_PTUSBHub failed to initialize`

在受限环境里，这条日志不一定代表代码有问题。

比如我在 Codex 的受限执行环境里就能看到这条日志，但模拟器相关能力和 MCP 握手依然是正常的。你在本机正常终端里使用时，这个行为会更接近真实环境。

## 当前边界

这一版先聚焦只读检查：

- 支持单会话
- 不支持同时连接多个 app
- 不提供属性修改
- 不提供方法调用
- 不输出 3D 渲染图

但对 agent 来说，树结构、节点 detail、单节点截图，已经够覆盖大部分 UI 排查场景。

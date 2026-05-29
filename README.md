<img width="543" height="724" alt="微信图片_20260529144350_109_23" src="https://github.com/user-attachments/assets/41a4081f-e191-4721-bdaf-f7e13bfb055f" /><img width="543" height="724" alt="微信图片_20260529144351_110_23" src="https://github.com/user-attachments/assets/d014929b-d176-4de5-a0b0-3833b3543947" />


# 盯盘 Bar — Mac 状态栏全市场行情监控

> 不抢屏、不打扰，A 股 / 港美股 / 基金 / 期货常驻 Mac 菜单栏。

对外宣传文案见 [MARKETING.md](./MARKETING.md)。

产品需求文档见 [PRODUCT_REQUIREMENTS.md](./PRODUCT_REQUIREMENTS.md)。后续功能变更以该文档为维护基准。

数据源：新浪行情 `hq.sinajs.cn`。涨跌按「现价 − 昨收」计算。

支持的市场：

| 市场 | 代码示例 | 交易时段（自动判断） |
|---|---|---|
| **期货 / 贵金属** | `AU9999`、`AUTD`、`AGTD`、`nf_AU0` | 贵金属按上金所时段；泛期货按日盘 + 夜盘粗略判断 |
| **A 股** | `600519`、`000001`、`sh600519` | 9:30–11:30 + 13:00–15:00 |
| **港美股** | `00700`、`hk00700`、`AAPL`、`gb_aapl` | 港股 9:30–16:00；美股 9:30–16:00 美东（自动处理 DST） |
| **基金** | `f_510300`、`fu_000001` | 按 A 股交易时段粗略判断 |

---

## Part 1 · Mac 状态栏原生 App（推荐）✅

### 功能
<img width="528" height="78" alt="微信图片_20260529144353_112_23" src="https://github.com/user-attachments/assets/a9d34285-b6aa-4165-9a22-fe653a41ed90" />

- **监控列表**：自定义最多 **30 条**，设置页按 **A 股 / 港美股 / 基金 / 期货** 四组维护。`AU9999` 严格说是上金所现货，但在产品里归入「期货」下的贵金属行情组。批量请求新浪 API，单次拉取。
- **状态栏轮播**：两种模式可切换 ——
  - **横向滚动**（默认）：所有项首尾相接连续左滑（无间隔参数），项与项之间留 3 个英文字符宽间隙，左右两侧渐隐遮罩。底层用 CALayer + Core Animation（GPU 合成），菜单弹出时也不卡。
  - **纵向切换**：一次只显示一项，每 N 秒（默认 3s，可调 1–30s）向上滑动到下一项。
  - 共用规则：所有监控项始终展示，不区分交易/休市状态。宽度固定到所有项里最宽那个，避免菜单栏抖动。
- **显示格式**：股票名小字号 + 价格菜单栏字号 + ▲/▼（涨/跌方向）+ 涨跌幅（1 位小数）+ 迷你走势图 + 「休市」小字（仅非交易时段展示，交易中无额外标记）。休市时展示截止收盘的涨跌幅和上一交易日走势。
- **迷你走势图**：股票优先使用当日分钟数据；非交易日沿用接口返回的上一交易日数据；贵金属、基金、期货或分钟数据失败时用 OHLC 降级图，保证不空窗。走势图结尾圆点按「现价 vs 开盘」显示涨跌颜色。
- **涨跌颜色**：设置页可切换「红涨绿跌 / 红跌绿涨」，默认红涨绿跌，影响走势图结尾圆点和到价提醒圆点。
- **价格提醒**：可预设最多 **10 条**阈值（涨到 / 跌到），可绑定监控列表中的**任意条目**（A 股、港股、美股、贵金属均支持）。价格穿越时在状态栏图标正下方弹**黑底浮层**（小红点/小绿点标识方向），鼠标 hover 即消失。分**单次**（触发即移除）和**重复**（每次穿越都触发）。
- **"还在刷"信号**：每次刷新成功状态栏短暂脉冲（120ms 暗→500ms 缓恢复）；超过 2 倍刷新间隔仍未拿到新数据 → 整行 alpha 0.5 提示陈旧。
- **刷新间隔**：默认 60s，可调 5–3600s。
<img width="1027" height="1440" alt="微信图片_20260529144352_111_23" src="https://github.com/user-attachments/assets/55189bcf-569d-43a4-b87f-f1fbffe1617d" />

### 文件结构

```
MacApp/
├── project.yml                # XcodeGen
├── setup_mac.sh               # 开发用：生成→编译→装到 ~/Applications→启动
├── release.sh                 # 对外分发：构建+ad-hoc 签名+打 dist/盯盘Bar-*.dmg
├── Config/Info.plist          # LSUIElement=YES（无 Dock 图标），CFBundleDisplayName=「盯盘 Bar」
└── Sources/
    ├── DingPanBarApp.swift    # App 入口 + AppDelegate
    ├── Market.swift           # 内部市场枚举：API 符号映射 + 交易时段判断
    ├── SymbolResolver.swift   # 用户输入代码 → 候选 symbol 自动识别
    ├── Quote.swift            # 通用行情数据
    ├── WatchedItem.swift      # 监控条目模型
    ├── WatchStore.swift       # 监控列表持久化 + v1→v2 迁移
    ├── QuoteFetcher.swift     # 自动识别 + 多市场批量拉取 + 四种解析器
    ├── Sparkline.swift        # 分钟走势抓取 + 迷你走势图渲染
    ├── SettingsStore.swift    # 刷新间隔 + 轮播间隔持久化
    ├── AlertModel.swift       # 提醒数据模型
    ├── AlertStore.swift       # 提醒持久化 + 穿越检测
    ├── RotatingStatusView.swift # 状态栏轮播视图（双 NSTextField 上滑切换）
    ├── HorizontalScrollStatusView.swift # 状态栏横向滚动视图（连续左滑 + 渐隐遮罩）
    ├── StatusController.swift # 主控制器：定时刷新 / 菜单 / 浮层
    ├── AlertPopupWindow.swift # 黑底浮层（hover 消失）
    └── AlertsWindow.swift     # SwiftUI 设置窗口
```

### 安装

**最终用户（一键安装包）**：拿到 `dist/盯盘Bar-1.2.dmg` → 双击挂载 → 把 `DingPanBar.app` 拖到 `Applications`。

**开发者（本机源码构建）**：

```
~/gold-au9999/MacApp/setup_mac.sh
```

脚本会：校验 Xcode → `xcodegen` → 编译 Release → ad-hoc 签名 → 装到 `~/Applications/DingPanBar.app` → 启动。再次运行即升级（自动杀旧进程）。

**对外分发**：

```
~/gold-au9999/MacApp/release.sh
```

构建 + ad-hoc 签名 + 打 DMG（经典拖拽到 Applications 界面），产物在 `MacApp/dist/`。

### 使用

1. **添加监控**：点状态栏图标 → 「设置…」→ 监控列表 → 在 A 股 / 港美股 / 基金 / 期货对应分组里点 `+`，填代码、可选自定义名称。市场会自动识别。
2. **设置间隔/颜色**：「设置…」顶部「通用设置」区可改刷新间隔、轮播方式、轮播间隔和涨跌颜色。状态栏菜单里也有快捷预设。
3. **设提醒**：「设置…」→ 价格提醒 → 加最多 10 条。每条提醒可通过下拉菜单选择绑定到监控列表中的任意条目（监控列表非空时生效）。
4. **开机自启**：系统设置 ▸ 通用 ▸ 登录项 ▸ + ▸ 选 `~/Applications/DingPanBar.app`。
5. **退出**：状态栏图标 → 「退出」。

### 数据持久化

- 监控列表：`UserDefaults` key `WatchedItems.v2`（兼容迁移 `WatchedItems.v1`）
- 通用设置：`UserDefaults` key `Settings.v2`
- 价格提醒：`UserDefaults` key `PriceAlerts.v1`

---

## Part 2 · Apple Watch（保留代码备用）

> ⚠️ 部署需要 Mac↔手表无线隧道，公司网/代理环境下经常建不起来。当前推荐用 Part 1 的 Mac 状态栏 App。手表方案保留代码备用，部署看 `WatchApp/setup_watch.sh`。

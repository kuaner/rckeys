# RCKeys

小米蓝牙遥控器 2 Pro（RC003）的 macOS 按键自定义工具。**纯按键，不含语音。**

把 13 个物理键映射成任何 Mac 动作：快捷键、媒体键、鼠标点击、打开 App、shell 命令；
每键支持单击 / 长按 / 双击 / 长按连发四种触发。后台常驻（无菜单栏图标）+ 可视化设置对话框
（遥控器实拍图点选按键 + 分组键位点选 + 真键盘录制）。

原生 Swift，仅一个第三方依赖（Sparkle 自动更新，SPM），Command Line Tools 即可构建。

## 架构（每一环都经 macOS 26 + RC003 真机验证）

```
RC003 ──BLE──▶ macOS
  ├─ ① hidutil 设备级哑化：12 键映射到键盘页 usage 0（No Event）
  │      系统对这台设备零反应（含 Secure Input 期间——没有系统事件就无所谓泄漏）
  │      --matching 限定 VID 0x2717 / PID 0x32B8，真键盘完全不受影响
  │      蓝牙每次重连后自动重新应用（registry 实例会变）
  └─ ② IOHID 纯监听（原始报告回调）→ 手势引擎 → CGEvent 注入
         无 CGEventTap、无时间窗抑制器、无 seize（macOS 26 已封死，见下）
```

与同类方案的区别：不拦截系统事件（哑化让事件根本不产生），所以不存在
抑制器误伤实体键盘、Secure Input 泄漏、退出残留乱键这类问题——残留的最坏表现
只是遥控器没反应，`rckeys --fix` 一键恢复。

## 快速开始

```bash
./build.sh              # 构建（单元测试：swift test）
.build/rckeys --test    # 12 秒试运行：应用映射、解码打印按键、自动恢复
.build/rckeys           # 后台常驻服务（无菜单栏图标；首次请求两项权限）
.build/rckeys --fix     # 异常退出后清理残留映射
```

| 权限 | 用途 |
|---|---|
| 输入监控 | IOHID 读取遥控器按键 |
| 辅助功能 | CGEvent 注入动作 |

**无菜单栏图标**：遥控器 **长按 菜单**（按住超过长按判定时长）呼出设置对话框——系统保留
手势，不可修改（菜单键的长按与连发位因此锁定；长按与单击按按压时长区分，零歧义、零延迟，
不像双击共存有时间窗问题）；暂停状态下同样有效。「服务」菜单（工具栏 ⋯）提供暂停/恢复、
重载配置（外部手改文件后应用）、编辑配置文件、清理映射并退出；窗口底栏显示接管状态（已接管 / 等待遥控器… / 已暂停）。
关闭窗口只是隐藏，服务继续运行。

**开机自启**：App 启动时自动安装 LaunchAgent
（`~/Library/LaunchAgents/com.kuaner.rckeys.plist`）——登录自启 + 崩溃自动拉起
（干净退出不会被拉起）；日志写入 `~/Library/Logs/rckeys.log`。开发用裸二进制运行不安装。
取消自启：退出 App 后删除该 plist 即可。

**不要与其他接管工具（Remote Mic 等）同时运行。**

## 设置对话框

遥控器 **长按 菜单** 呼出——一次只面对一个决策的三层结构：

- 左侧遥控器实拍图，点选任意按键（选中/悬停高亮）；
- 右上 4 张触发卡（单击/长按/双击/连发）各显示当前动作摘要，点选要编辑的那一个；
- 右下只编辑选中的触发：动作类型卡（按键/媒体键/鼠标/打开App/Shell/无动作）是
  **纯查看切换**——点开任意类型浏览参数界面不会改动现有配置，只有在参数区做出
  明确选择（点键位/录制/点媒体键/选 App/输入命令）时才写入保存；
  **试一试**当场执行一次验证，清除一键取消配置；
- 按键动作用分组键位面板点选拼装 + 真键盘录制（按住单个修饰键 0.7 秒 =
  录为单修饰键动作，适配「长按 fn 说话」类输入法），键帽式显示；
- 媒体键为图标网格（含快进/快退）；打开 App 显示已选 App 图标；
- 长按与连发互斥由界面自动处理（配置其一自动清除另一个并提示）；
- **改动自动保存并热生效**，无需手动保存；全局手感参数在「手感设置」弹窗；
- 支持单键恢复出厂键位，全部恢复默认有二次确认。

配置文件：`~/Library/Application Support/RCKeys/config.json`。界面改动**保存即生效**（进程内直通，不依赖文件监听）；外部手改文件后用「服务 ⏷ → 重载配置」应用（文件仅启动与此处被读取）。

```jsonc
{
  "settings": { "holdMs": 350, "doubleMs": 250, "repeatMs": 100, "repeatDelayMs": 350 },
  "keys": {
    "up":     { "tap": {"type":"key","combo":"arrowup"}, "repeat": {"type":"key","combo":"arrowup"} },
    "back":   { "tap": {"type":"key","combo":"delete"}, "hold": {"type":"key","combo":"esc"} },
    "tv":     { "tap": {"type":"key","combo":"cmd+tab"}, "hold": {"type":"key","combo":"cmd+shift+tab"} },
    "volup":  { "tap": {"type":"media","name":"volume_up"}, "repeat": {"type":"media","name":"volume_up"} },
    "menu":   { "tap": {"type":"mouse","name":"right"} },
    "power":  { "tap": {"type":"key","combo":"ctrl+cmd+q"},
                "hold": {"type":"shell","command":"pmset displaysleepnow"} },
    "voice":  { "hold": {"type":"key","combo":"fn"} }   // 长按=按住 fn（自动松开）
  }
}
```

- 键名：`up down left right ok back home menu tv power volup voldown voice`
- 触发：`tap`（未配 double 时零延迟；按压超过长按判定的松手不会触发单击——
  算长按）/ `hold` / `repeat`（连发，与 hold 互斥）/ `double`
- 动作：`key`（combo：`ctrl+cmd+q`、`arrowup`、`f5`、裸修饰键 `fn`…）/ `media`
  （volume_up/down、mute、brightness、play、next、prev）/ `mouse`（left/right）/
  `open`（选择后存 bundle id，App 改名/更新不受影响；旧配置的 App 名兼容）/ `shell` / `none`
- `hold` 配置为裸修饰键时自动变为**按住语义**：触发时按下、松手时释放，
  断连/暂停自动补释放，不会卡键。

## 默认键位

| 键 | 单击 | 长按 |
|---|---|---|
| 方向 | 方向键 | 连发 |
| OK | 回车 | — |
| 返回 | 删除 | Esc |
| 主页 | 调度中心 | Ctrl+↑ |
| 菜单 | 鼠标右键 | — |
| TV | Cmd+Tab | Cmd+Shift+Tab |
| 音量± | 音量（OSD） | 连发 |
| 电源 | 锁屏 | 屏幕睡眠 |
| 语音 | 无动作（自配，常见：长按=fn） | — |

菜单键的**长按**为系统保留手势（呼出设置），不可配置；连发位也因此锁定。

## 已知发现（对同类项目有复用价值）

以下均为 macOS 26 + RC003（固件 2671）真机实测，探针源码见 `probes/`：

1. **seize 被系统拒绝**：输入监控权限齐备时，`IOHIDDeviceOpen(kIOHIDOptionsTypeSeizeDevice)`
   仍返回 `kIOReturnNotPrivileged`（0xE00002C1）。macOS 26 上用户态独占蓝牙键盘不可行，
   「seize 优先、失败降级」的代码在新系统永远跑在降级分支。
2. **macOS 26 媒体键事件编码变更**：NX_SYSDEFINED(subtype 8) 的 `data1`
   需为 `键码<<16 | 状态<<8`（状态 0xA 按下/0xB 释放）。流传已久的老配方
   `状态<<8 | 键码` 在 26 上键码落入被忽略字段，**所有媒体键都会变成音量加**
   （音量减、静音全部失效）。已用系统音量读数做前后对照验证（见 Actions.postNX 注释）。
3. **哑化不影响监听**：UserKeyMapping 映射到 usage 0 后，IOHID 的原始报告回调与
   值回调仍收到**原始 usage**——「内核哑化 + 纯监听」链路完整可用。
4. RC003 按键报告格式：`reportID(1B) + N×小端 u16 usage 槽`（实测 7 字节 / 3 槽）；
   值回调中存在 usage 0xFFFFFFFF 噪声元素需过滤；返回键 0xF1 超出键盘页标准范围，
   系统天然不处理、hidutil 不接受映射，无需哑化。
   **并发按键不可用（已充分实测）**：用双通道探针（`probes/duallisten.swift`，原始报告层 +
   值回调层同时监听）验证了 OK+方向、方向+OK、音量+与音量−同按、OK+菜单四组组合，
   无任何一份报告出现第二个 usage、值回调亦然——固件在 macOS 配对下不上报并发按键，
   组合键触发在本机不可实现。值回调中另有 usage 0x1（ErrorRollOver）元素随报告翻转的噪声。
   参考：[godarrenw/mi_remote_control](https://github.com/godarrenw/mi_remote_control) 记录的
   Windows 侧抓包为 9 字节 / 3 槽多键报告——不同系统协商的报告格式不同（我们实测 7 字节）；
   其 OK+方向手势未列入实机已验证项，与本文结论一致。多键触发只能用「先 A 后 B」
   短时序列实现。
5. RC003 身份信息：GATT 暴露 `180F/180A/ATVV(AB5E0001)/8A7A0001(私有)/01BF/FE59(Nordic
   Secure DFU)`；Device Information 为 Manufacturer `MIOM` / Model `RC003` /
   HW `V2.0` / FW `2671` / SW `A.7.0.6`。Type-C 为纯充电口（USB 树零枚举）。

## probes/（研究探针）

| 工具 | 用途 |
|---|---|
| `gattdump.swift` | 全 GATT 服务/特征枚举 + 只读 dump（JSON 存档） |
| `seizetest.swift` | seize 可行性探针（含 ReportDescriptor 抓取） |
| `duallisten.swift` | 双通道监听：验证哑化后原始报告层与值回调层是否存活 |

均为独立 swift 单文件，`swiftc -O xxx.swift -o xxx` 编译，只读不写设备。

## 安装与发布

- **安装**：从 GitHub Releases 下载 DMG，拖入「应用程序」。也可源码运行：
  `./build.sh && .build/rckeys`（构建；单元测试 `swift test`）。
- **本地打包**：`scripts/build_app.sh release` —— SPM 双架构通用二进制（Swift 6 语言模式），
  组装 `RCKeys.app`（无 Dock/菜单栏图标），产出 `dist/RCKeys-<版本>-universal.dmg`；
  版本可用 `VERSION=` 覆盖（CI 从 tag 取）。配置 `.secret.env`（见 `.gitignore`，
  含 APPLE_SIGNING_IDENTITY / APPLE_ID / APPLE_APP_SPECIFIC_PASSWORD / APPLE_TEAM_ID）
  后自动升级为 **Developer ID 签名 + notarytool 公证 + staple**，否则降级 ad-hoc。
- **图标**：`swift scripts/make_icon.swift` 可复现生成 `assets/AppIcon.icns`。
- **发布**：`git tag vX.Y.Z && git push --tags` → GitHub Actions
  （`.github/workflows/release.yml`）自动构建（仓库 secrets 配置同上组密钥 +
  p12 相关三项）并创建 Release 附 DMG；push/PR 由 `ci.yml` 跑 `swift test` + `./build.sh`。
- **自动更新**（Sparkle）：内置每日自动检查 + 「服务 ⏷ → 检查更新…」手动触发；
  发布时 CI 用 EdDSA 私钥（GitHub secret `SPARKLE_PRIVATE_ED_KEY`，公钥嵌在
  App 的 Info.plist）签名 DMG 并把 `appcast.xml` 部署到 gh-pages
  （`https://kuaner.github.io/rckeys/appcast.xml`），App 内置该更新源。

## 故障排查

- **遥控器没反应**：遥控器**长按 菜单**打开设置，看窗口**底栏状态**——
  「等待遥控器…」= 蓝牙未连接；「输入监控权限未授予」= 系统设置 → 隐私与安全性 →
  输入监控，勾选 RCKeys 后**重启 App**；「已暂停」= 「服务 ⏷」里恢复接管；
  都正常仍无反应则跑 `.build/rckeys --fix` 清理残留映射。
- **按键有动作但系统也在动**：哑化未生效（蓝牙重连竞态）——「服务 ⏷」暂停再恢复一次。
- **单击/双击不跟手**：手感设置里调「双击窗口」（窗口越大双击越灵、单击越钝）与
  「长按判定」；按压超过长按判定的松手视为长按，不会触发单击。
- **fn 松开弹表情选择**：系统设置 → 键盘 → 「按下 🌐 键时」→「什么都不做」。
- **重启后 App 没有自动运行**：检查 `~/Library/LaunchAgents/com.kuaner.rckeys.plist`
  是否存在（App 正式安装并运行过一次后自动生成）。

## 许可与致谢

代码 MIT（LICENSE）；`Resources/RC003-remote-photo.png` 与热点坐标取自
[HD838A/remote-mic-app](https://github.com/HD838A/remote-mic-app)（GPL-3.0），
详见 THIRD_PARTY_NOTICES.md。

# AGENTS.md

RCKeys：小米蓝牙遥控器 2 Pro（RC003）的 macOS 按键自定义工具。菜单栏常驻，
把 13 个物理键映射为快捷键/媒体键/鼠标/打开 App/shell，支持单击/长按/双击/连发。
原生 Swift、零第三方依赖。改架构相关代码前先读 README.md 的「已知发现」一节。

## 构建与测试

```bash
swift test                  # 单元测试（Swift Testing）：引擎虚拟时钟边缘用例 + 模型层
./build.sh                  # swiftc -O 编译 CLI（单模块直编，不走 SPM）
.build/rckeys --test        # 12 秒真机试运行：应用哑化、打印解码、自动恢复
.build/rckeys --fix         # 清理 hidutil 残留映射（调试崩残留时用）
scripts/build_app.sh release  # 打包 RCKeys.app（通用二进制）+ 签名公证 + DMG
swift scripts/make_icon.swift # 重新生成应用图标 assets/AppIcon.icns
```

- 目录结构：`Sources/RCKeys/` 为逻辑库（SPM 测试目标，`@testable` 免 public）；
  `Sources/main.swift` 为 CLI/App 入口。生产构建用 swiftc 把两者编成**单一模块**
  （不需要 SPM）；`Package.swift` 仅供 `swift test`。语言模式固定 v5。
- 手势引擎的时钟可注入（`GestureEngine.Scheduler`）：生产主队列真实时钟，
  测试用 `VirtualClock` 确定性推进——改引擎时序逻辑必须补对应测试。
- 无 Xcode 工程、无 lint；只需 Command Line Tools。`.build/`、`dist/` 已 gitignore。
- 发布：push tag `v*` 触发 GitHub Actions 出 Release；push/PR 由 ci.yml 跑 `swift test` + `./build.sh`。
- 注释、文档、UI 文案均为中文，保持一致。

## 架构（核心链路，勿破坏）

```
hidutil 设备级哑化(12 键 → usage 0) + IOHID 纯监听(原始报告回调)
  → GestureEngine(手势判定) → Actions(CGEvent 注入)
```

**明确不用**：CGEventTap、时间窗抑制器、seize（macOS 26 上 seize 必然返回
kIOReturnNotPrivileged）。这是设计决策，不是待修 bug。

各文件职责：

| 文件 | 职责 |
|---|---|
| `Sources/main.swift` | CLI 子命令、组件装配、自检 |
| `Sources/Remap.swift` | hidutil 哑化的 apply/clear（`--matching` 限定 VID 0x2717/PID 0x32B8） |
| `Sources/HID.swift` | RC003 usage 表 + KeyListener（IOHIDManager 原始报告回调 → 按键边沿） |
| `Sources/Gesture.swift` | 手势引擎：tap/hold/repeat/double，连发由引擎定时器驱动；长按菜单系统保留（onSystemGesture 呼出设置，菜单 hold/repeat 位锁定） |
| `Sources/Actions.swift` | 动作执行：CGEvent 按键、NX_SYSDEFINED 媒体键、鼠标、open、shell |
| `Sources/Service.swift` | 后台服务枢纽：ServiceStatus（对话框底栏状态）、ServiceHub（对话框菜单 → Agent 动作）、系统保留呼出手势（长按菜单）、AutoStart（LaunchAgent 自启安装） |
| `Sources/Updater.swift` | Sparkle 自动更新（`#if canImport(Sparkle)`——仅打包构建含更新组件，开发构建 `build.sh` 无框架自动裁剪） |
| `Sources/Config.swift` | RemoteKey 枚举(13 键)、Action/KeyConfig 模型；配置存 `~/Library/Application Support/RCKeys/config.json` |
| `Sources/ConfigUI.swift` | 可视化配置窗口：触发卡+单编辑器布局、自动保存（防抖写盘→热加载）、手感设置 Sheet |
| `Sources/ActionEditor.swift` | 动作类型卡与各参数编辑器、键帽渲染、可读描述 `Pretty`、真键盘录制 `ComboRecorder` |

## macOS 26 / RC003 硬约束（真机实测，详见 README）

- **媒体键编码**：NX_SYSDEFINED(subtype 8) 的 `data1` 必须是 `键码<<16 | 状态<<8`
  （0xA 按下 / 0xB 释放）。老配方 `状态<<8 | 键码` 会让所有媒体键变成音量加。
  见 `Actions.postNX` 注释。
- **哑化不影响监听**：UserKeyMapping 映到 usage 0 后，IOHID 原始报告回调仍收到
  原始 usage，所以「内核哑化 + 纯监听」链路成立。
- **蓝牙重连后 registry 实例变化**，必须由设备回调重新应用哑化，否则系统恢复默认行为。
- **报告格式**：`reportID(1B) + N×小端 u16 usage 槽`；值回调有 0xFFFFFFFF 噪声需过滤；
  返回键 0xF1 超出键盘页，系统不处理、hidutil 不映射，无需哑化（`Remap.neuters` 有 12 项）。
- **运行时权限**：输入监控（IOHID 读键）+ 辅助功能（CGEvent 注入），首次运行各弹一次。
- 不要与其他接管工具（Remote Mic 等）同时运行。

## 许可注意

代码 MIT；`Resources/RC003-remote-photo.png` 与热点坐标来自 GPL-3.0 项目
（见 THIRD_PARTY_NOTICES.md），不要把该资源混入 MIT 许可的部分。
`probes/` 为独立研究探针（`swiftc -O xxx.swift -o xxx` 单文件编译），只读不写设备。

# 第三方资源声明

## RC003 遥控器照片（`Resources/RC003-remote-photo.png`）

取自 [HD838A/remote-mic-app](https://github.com/HD838A/remote-mic-app)（GPL-3.0），
配置界面的按键热点归一化坐标同样参考其 `RemoteMappingLayout`。该文件遵循 GPL-3.0；
本仓库其余代码为 MIT（见 LICENSE）。不使用此照片时代码仍可运行（界面回退为占位矩形）。

## 协议知识

RC003 的 ATVV 语音协议、HID usage 表、报告格式来自公开开源生态的多份互相印证的实现
（open-voice-bridge / remote-mic-app / mi-ao / rctool / mi-remote-gateway 等）。
本项目仅使用其中的按键 HID 部分，未实现语音链路；全部按键通道行为均在本机实测验证。

## macOS 26 媒体键事件编码

`Actions.postNX` 使用的新版 NX_SYSDEFINED data1 布局（键码 16-23 位 / 状态 8-15 位）
为本项目独立实测发现，见 README「已知发现」一节。

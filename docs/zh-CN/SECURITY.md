# 安全政策

**简体中文** · [繁體中文](../zh-TW/SECURITY.md) · [English](../../SECURITY.md) · [日本語](../ja/SECURITY.md)

Wizard 面向旧款 iPad，使用外部媒体路径、局域网媒体控制和 Apple 私有框架。使用前请阅读[隐私与网络说明](PRIVACY.md)及[兼容性范围](COMPATIBILITY.md)。

## 报告漏洞

仓库启用 GitHub 私密漏洞报告后，请通过[私密漏洞入口](https://github.com/rexchen1803/wizard/security/advisories/new)报告。不要在公开 Issue 中发布未修复漏洞、凭据、私有日志、设备标识或个人媒体。请注明受影响的源码版本或 Wizard build、相关 iPad 型号和系统，以及简短复现步骤；删去个人与网络详情。

若私密报告入口尚不可用，请保留漏洞细节，等待私密渠道开放，不要改用公开 Issue 披露。项目暂不承诺响应时限或支持周期。

## 安全审查范围

同时审查主 App、可选电源插件、安装器和发布导出。移除界面或 URL 入口不等于关闭后台监听或特权 IPC 接收端。网络控制与诊断须主动启用，源码、构建和设备证据分别核对。

## 版本支持

目前没有承诺设备支持的正式版本。当前候选与验证范围见[兼容性指南](COMPATIBILITY.md)。宿主机回归不能证明设备安全性或运行支持。

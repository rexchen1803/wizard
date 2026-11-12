# WizardPower（可选实验组件）

此组件接入 SpringBoard 的私有接口，响应电源连接、断开、锁屏和唤醒。它与主 App 分开；普通时钟、图库和本地视频不依赖该组件。App 的 `.deb` 预览包不会自动安装它，也不会自动重启 SpringBoard。

在 Mac 上，使用自行获得的 iPhoneOS SDK：

```sh
IOS_SDK="/path/to/iPhoneOS9.3.sdk" ./scripts/build-power.sh --out power-build
```

输出 `WizardPower.dylib`（armv7 + arm64）、过滤 plist 和构建记录。源码不使用 Logos 指令，因此该构建入口直接调用 Apple clang，不需要分发或安装历史 Theos 工作区。

这只证明动态库能构建，不能证明私有接口在某台设备上可用。安装需要单独验证 rootful 越狱的 tweak 注入方式、签名和兼容性；若没有匹配的设备验收，不启用电源自动化。Agent 默认跳过该组件，不复制电源偏好、不修改锁屏或信任策略。没有在本轮设备上安装或测试此组件。

为关闭未鉴权的跨 App 控制通道，本版本不再注册远程锁屏、唤醒或状态查询的 Darwin 通知。电源线连接/断开的本地自动化保留。诊断日志仅在存在临时 `/tmp/wizardpower-debug` 标记时写入。

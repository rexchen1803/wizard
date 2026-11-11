# Agent 安装提示词

Copy this prompt to authorize one Wizard preview installation on the currently connected, already prepared iPad. It authorizes the package download and install, one app stop if Wizard is running, and an intact rollback bundle for an update. No repeated confirmation is needed for those steps. It does not authorize changes outside this package flow.

```text
我授权你在当前连接的、已经准备好的 iPad 上安装 Wizard 预览版一次，并授权为更新保留完整旧 app 回滚包、最多停止 Wizard 进程一次。此授权只限下面固定的版本、当前设备和本次安装。按以下步骤执行，不要重复询问已授权步骤：

1. 先只读检查设备型号、iOS 版本、rootful 越狱/包管理器状态、/Applications 是否为可写且非符号链接目录、ldid/uicache/killall 是否可用，以及是否已安装 com.rex.wizardsystem。可使用已经配置且获准的本地 USB 或 SSH 通道读取身份；不要创建账号、修改密码、启用 SSH 或设置网络/证书/信任。
2. 对照仓库 docs/INSTALL.md。只接受 iPad2,4 + iOS 9.3.5、iPad3,4 + iOS 10.3.3、iPad4,1 + iOS 12.5.8 这三种配对。连接通道已配置而缺少凭据时，只询问该凭据；目标设备不明确时，只询问目标设备。unsupported/stock/rootless 状态下停止，不要尝试建立或修复越狱。
3. 下载并校验这个固定版本，不替换为 `latest`：
   https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.1/wizard_0.2.0-20261111.37_iphoneos-arm.deb
   从同一 Release 下载 .deb.manifest.json，并在下载后核对 SHA-256。链接、文件名、包版本或校验值不一致就停止。
4. 检查通过后，直接使用设备现有的 Cydia、Sileo、Zebra 或 Filza 包管理流程安装此 .deb；这一步已由本提示授权。更新时可以停止正在运行的 Wizard 一次，并由安装器把旧 bundle 保存在 WizardSystem.rollback-*。不得安装电源 tweak，不得打开 Wizard、respring、重启或操作其他 app。
5. 安装后只读回读 bundle id/version/build、app 路径、包管理器结果和媒体/偏好设置是否仍存在；不要读取或输出媒体内容或偏好设置值。清楚报告“此 build 尚无设备验收”。
6. 若安装失败或无法读取关键状态，保留所有 WizardSystem.app、WizardSystem.rollback-*、WizardSystem.uninstalled-* 和 WizardSystem.failed-* 目录，报告原始错误并停止。不要删除用户数据或自行猜测修复。

只有当任务还要求卸载本 Debian 包时，才执行包管理器 remove。卸载钩子只会注销与包 build 匹配的 Wizard app，并把完整 bundle 保存在 WizardSystem.uninstalled-*；媒体、偏好和已有 rollback 包保留。需要恢复时，重新安装固定 .deb，再使用 docs/INSTALL.md 的 helper rollback 命令。不要让 dpkg 清理或手动删除任何恢复 bundle。

下载 Rockstar 媒体是单独选择：本次授权不含媒体下载或安装。只有我另行要求时，才使用 docs/INSTALL.md 固定的 gallery 包；先备份 /var/mobile/Media/iPadWizard/app，再把 ZIP 中 app/ 内容合并到该目录，绝不替换整个 app 目录，保留 assets/user。原始资料包不是设备安装包。Rockstar attribution 不等于再分发许可。
```

The release links in this prompt are pinned to `v0.2.0-preview.1`; do not replace them with a moving `latest` link. An agent prompt, source build, valid checksum, and package-manager success are separate from physical-device acceptance.

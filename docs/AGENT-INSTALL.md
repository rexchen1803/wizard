# Agent 安装提示词

**简体中文** · [繁體中文](zh-TW/AGENT-INSTALL.md) · [English](en/AGENT-INSTALL.md) · [日本語](ja/AGENT-INSTALL.md)

将下面的完整提示词交给 Codex 或其他 Agent，表示你授权在当前连接、已准备且明确指定的一台 iPad 上尝试安装一次 Wizard 预览包。授权仅限 build `20261112.40`、该设备和本次安装；授权覆盖只读检查、获取并校验固定安装包、安装一次、更新时最多停止 Wizard 一次，以及保留安装器生成的完整回滚 bundle。它不授权越狱、改密码、配置连接、安装电源插件、启动 App、respring、重启或修改仓库发布状态。

仓库目前为私有仓库，所有 Release 均为草稿。`v0.2.0-preview.4` 没有公开下载端点。下面的固定下载地址标为**发布后才可用**；Agent 必须先确认固定 `.deb` 与配套清单能通过已获准的现有仓库访问方式取得。如果文件不可用，必须在联系设备前停止报告，不能发布 Release、改变仓库可见性、改用 `latest` 或其他版本。

## 提示词

```text
我授权你仅在当前已连接、已准备、且我明确指定的那一台 iPad 上，尝试安装 Wizard 0.2.0 / build 20261112.40 一次。授权只覆盖本提示中列出的只读检查、获取和校验固定安装包、一次安装、更新时由安装器最多停止 Wizard 一次，以及保留完整旧 App 回滚 bundle。不要重复询问这些已授权步骤；目标设备不明确时只询问目标设备。不要超出下面的设备、版本和操作范围。

仓库当前是私有仓库，所有 GitHub Release 都是草稿。v0.2.0-preview.4 尚未发布，以下 GitHub 下载路径是未来固定地址，目前没有公开下载端点。先用当前已获准的仓库访问方式确认固定 .deb 和对应 manifest 文件实际可取得；如果任一文件不可用，立即停止并报告，不要连接或操作设备。不得发布 Release、改变仓库可见性、创建下载端点、使用 latest、改用其他版本或从非指定来源取得替代包。维护者 Release 页面仅作获准账户查看草稿的入口：https://github.com/rexchen1803/wizard/releases

发布后唯一接受的 build40 文件及固定路径：
- wizard_0.2.0-20261112.40_iphoneos-arm.deb
  https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.4/wizard_0.2.0-20261112.40_iphoneos-arm.deb
- wizard_0.2.0-20261112.40_iphoneos-arm.deb.manifest.json
  https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.4/wizard_0.2.0-20261112.40_iphoneos-arm.deb.manifest.json

1. 在任何设备连接前，确认两个固定文件均可从获准来源取得，文件名、包版本和 manifest 对应一致，并核对 .deb 的 SHA-256 等于 manifest 中的 artifact_sha256。任何文件缺失、哈希不符、版本不符或来源不同，都停止并报告；不要继续设备检查。
2. 只有在第 1 步全部通过后，才对唯一目标设备做只读预检：读取精确型号和 iOS 版本，确认 rootful 越狱、Debian 包管理环境、root 权限、可写且非符号链接的 /Applications，以及 sysctl、sw_vers、ldid、uicache 和 killall 是否可用。检查 Wizard bundle 是否已安装。只能使用已配置并获准的本地 USB 或 SSH 通道；不得创建账号、修改密码、启用 SSH、改网络、装证书或改变信任设置。若该通道已配置并获准但缺少登录凭据，只询问该凭据；连接失败或需要其他未授权配置时停止。
3. 只接受以下精确型号与系统配对：iPad2,4 + iOS 9.3.5；iPad3,4 + iOS 10.3.3；iPad4,1 + iOS 12.5.8。未越狱原版 iOS、rootless 越狱、iPhone 或任何其他型号/版本均停止，不要试图建立或修复越狱，也不要绕过预检。
4. 预检通过后，通过设备现有的 Cydia、Sileo、Zebra、Filza 或已获准的 rootful dpkg 流程安装该固定 .deb。此处的单次安装已获本提示授权。更新时安装器最多向 Wizard 发送一次 TERM，并把原有 WizardSystem.app 完整保留为 WizardSystem.rollback-<build>-<UTC>.app。它会使用设备已有的 ldid 签名，并调用 uicache 注册；不要安装电源 tweak、启动 Wizard、respring、重启或操作其他 App。首次安装没有旧 App 回滚 bundle。
5. 安装后只读核对 bundle ID、版本、build、App 路径、包管理器结果及媒体目录和偏好设置是否仍存在。不要读取、复制或输出媒体内容或偏好设置值。不要启动 App；明确报告：“build 20261112.40 尚无物理设备验收”。安装器成功或包管理器返回成功都不等于用户已验收。
6. 安装失败、关键状态无法读取、或安装器报告任何错误时，原样记录错误并停止。保留所有 WizardSystem.app、WizardSystem.rollback-*、WizardSystem.uninstalled-* 和 WizardSystem.failed-* 目录；不删除、覆盖、手动修复或猜测清理任何数据，也不强制 respring 或重启。

除非我在另一个明确请求中要求卸载，否则不要卸载 Debian 包。获准卸载时，包管理器的卸载钩子只注销 build 与包匹配的 Wizard App，并把完整 bundle 保留为 WizardSystem.uninstalled-<build>-<UTC>.app；媒体、偏好设置和既有回滚 bundle 保留。若需恢复，重新安装同一固定 .deb 取回 helper，再按 docs/INSTALL.md 的 rollback 说明使用真实的 WizardSystem.uninstalled-* 路径。不得让 dpkg 或手动命令清理恢复 bundle。

本授权不包含下载或安装 Rockstar 媒体。只有我另行明确要求图库安装时才可处理图库。图库也在未发布的 v0.2.0-preview.4 草稿中；如果附件无法通过获准方式取得，停止，不得发布 Release 或改变仓库可见性。发布后唯一接受的图库文件为 wizard-gta6-gallery-20261112.zip，SHA-256 必须是 b8bd883b81a0a76086217ce3c27091d83b0b8261dcbabae49c88abb67aef3eba；固定未来地址为：
https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.4/wizard-gta6-gallery-20261112.zip
若我明确授权安装该图库，先完整备份 /var/mobile/Media/iPadWizard/app，再核对哈希，把 ZIP 中 app/ 的内容合并到此目录。绝不替换整个 app/，保留 assets/user、用户导入照片和偏好设置。原始素材包不是设备图库安装包。Rockstar 素材来源标注不等于获得再分发许可。
```

源代码构建、提示词授权、SHA-256 校验、安装器成功和物理设备验收是不同的证据。设备验收范围见[兼容性指南](COMPATIBILITY.md)，完整安装与恢复说明见[安装指南](INSTALL.md)。

# 安装 Wizard

当前候选是 [v0.2.0-preview.3](https://github.com/rexchen1803/wizard/releases/tag/v0.2.0-preview.3) 预览版。提供 `.deb` 安装包、源码构建和 [Agent 安装提示词](AGENT-INSTALL.md)。安装包面向已经准备好的 **rootful 越狱 iPad**；不安装越狱，不修改证书、网络或系统信任，不自动安装电源插件。

## 先核对设备

当前安装器只接受以下精确型号与系统配对：

| 设备 | 型号标识 | iOS |
| --- | --- | --- |
| iPad 2 | `iPad2,4` | `9.3.5` |
| iPad 4 | `iPad3,4` | `10.3.3` |
| iPad Air | `iPad4,1` | `12.5.8` |

还需要：root 权限、可写且非符号链接的 `/Applications`、现有 Debian 包管理环境，以及 `ldid`、`uicache`、`killall`、`sysctl`、`sw_vers` 等工具。`uicache` 需要支持 `-p` 注册和 `-u` 取消注册。原版未越狱 iOS、rootless 越狱、iPhone 和未列出的型号/版本会被拒绝。更多型号属于待验证范围，不能靠改型号绕过预检。

包结构和安装器预检已通过本机夹具检查；这不等于已完成设备上的安装、签名、注册和启动。早期准备环境中的真机记录见 [兼容性表](COMPATIBILITY.md)，不能直接作为本预览版首次安装的验收。

## 方式一：直接安装

1. 在上述设备的现有环境中下载 [Wizard `.deb`](https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.3/wizard_0.2.0-20261112.39_iphoneos-arm.deb) 和 [包清单](https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.3/wizard_0.2.0-20261112.39_iphoneos-arm.deb.manifest.json)。
2. 核对 SHA-256 与清单中的 `artifact_sha256`。Mac 上可用 `shasum -a 256 文件名.deb`；不要混用其他版本的包和清单。
3. 用设备上已经安装的 Filza，或 Cydia / Sileo / Zebra 支持的本地 `.deb` 流程打开并安装。已授权的设备 root 终端也可以使用：

   ```sh
   dpkg -i ./wizard_0.2.0-20261112.39_iphoneos-arm.deb
   ```

4. 安装器先检查环境，在设备上用现有 `ldid` 为 App 做 ad-hoc 签名，然后更新 App 注册。更新时只关闭 Wizard 一次，不重启设备或 SpringBoard，也不自动打开 App。安装完成后可由你手动打开 Wizard 验收。

已有 Wizard 会先保留为 `WizardSystem.rollback-<build>-<UTC>.app`，再原子替换 App。媒体目录 `/var/mobile/Media/iPadWizard/app`、照片导入、收藏、裁切、时钟布局和偏好文件均不在包的替换范围内。首次安装没有旧 App 时会走独立分支。

预检失败会在替换 App 前停止；包管理器可能保留待配置状态。签名或注册失败时，按错误保留所有现有 App、候选和回滚目录，先报告错误，不要强制 respring 或删除用户数据。

## 方式二：交给 Agent

打开 [AGENT-INSTALL.md](AGENT-INSTALL.md)，复制完整提示词给 Codex、Claude Code 等。提示词限定设备范围、已有授权、备份、校验与回滚；缺少目标设备或授权连接时先补齐，不使用默认密码或创建新的越狱/信任配置。

## 方式三：从源码构建

在 Mac 上安装 Apple 开发工具，自行准备 iPhoneOS SDK。当前验证 SDK 为 iPhoneOS 9.3；较新 SDK 的 armv7 与旧 MediaPlayer 接口兼容性待验证。

```sh
git clone https://github.com/rexchen1803/wizard.git
cd wizard
IOS_SDK="/path/to/iPhoneOS9.3.sdk" ./scripts/build-ipad.sh --out /tmp/WizardSystem-build
python3 scripts/package-release.py \
  --app /tmp/WizardSystem-build/WizardSystem.app \
  --out /tmp/wizard_0.2.0-20261112.39_iphoneos-arm.deb
```

输出目录/文件必须尚不存在。构建生成未签名的 `armv7 + arm64` App、三张图标、两张横版启动图和 `BUILD-METADATA.txt`；打包器核对架构、源指纹、bundle ID、资源字节与尺寸，并生成 `.deb` 及相邻 manifest。构建与打包都不会连接设备或执行安装。

给打包命令加 `--dry-run` 可只输出包结构与哈希，不写安装包。完整源码与回归命令见 [技术构建指南](open-source/README.md)。可选的 [WizardPower 源码](../App/WizardPowerTweak/README.md) 有独立构建入口，不随 App 自动安装。

## 安装可选 GTA VI 图库

[App 图库包](https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.3/wizard-gta6-gallery-20261112.zip) 包含230项目录、228张图片、2段视频与缩略图。校验值见 [素材清单](../assets/media/MANIFEST.json)。[原始素材包](https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.3/gta6-original-materials-20261112.zip) 用于收藏和制作，不是设备图库安装目录。

1. 先完整备份设备上的 `/var/mobile/Media/iPadWizard/app`。
2. 将图库 ZIP 的 `app/` 内容**合并**到该目录，保留现有 `assets/user` 和偏好文件；不要删除或整目录替换旧 `app`。
3. 确保目录可供 `mobile` 用户遍历、文件可读。素材包普通文件的权限已设为 `0644`；若传输工具改写了权限，按实际所属用户修正这些新复制文件，避免递归改动已有用户目录。
4. 重新打开 Wizard，核对分类、原壁纸、收藏、裁切和用户照片是否保留。

GTA VI 图片、视频及衍生素材版权属于 Rockstar Games 及相应权利人。两个素材包有独立文件清单和 [版权署名](../assets/media/ATTRIBUTION.md)，不适用 Wizard 的 MIT 源码许可。

## 回滚与卸载

更新完成后记下安装器打印的精确回滚目录。在设备上已授权的 root 终端执行：

```sh
/usr/lib/wizard-installer/install-wizard.sh rollback /Applications/WizardSystem.rollback-20261112.39-20261112T120000Z.app
```

示例时间戳需要替换为实际值。helper 会保留当前候选，恢复所选回滚目录并更新 App 注册；它不自动启动 App，也不重启 SpringBoard。失败时保留所有目录，不猜测删除或覆盖。

通过包管理器卸载，或在设备 root 终端执行 `dpkg -r com.rex.wizardsystem`。卸载钩子只处理 bundle ID 和 build 与当前包一致的 Wizard：将 App 完整保留为 `WizardSystem.uninstalled-<build>-<UTC>.app`，取消其注册，保留媒体、偏好和既有回滚目录；普通升级不会触发卸载分支。

卸载后如要恢复，先重新安装同一 `.deb` 取回 helper，再用上述 `rollback` 命令指向实际的 `WizardSystem.uninstalled-*` 目录。若设备状态或 App build 与包不一致，先报告状态，不强制删除未知 App。清除个人媒体/偏好属于另外的操作，不随普通卸载执行。

App 内含一张已署名的 Vice City 默认壁纸；未安装外部图库时可直接显示。完整图库包可选，原有目录、导入照片及设置应在合并前备份。

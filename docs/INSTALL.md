# 安装 Wizard

**简体中文** · [繁體中文](zh-TW/INSTALL.md) · [English](en/INSTALL.md) · [日本語](ja/INSTALL.md)

本文介绍 Wizard 0.2.0 / build `20261112.41` 的预览安装包、源码构建、可选图库和回滚方式。安装包仅面向已准备好的 **rootful 越狱 iPad**；它不会安装越狱、安装电源插件、修改证书、网络或系统信任设置，也不会自动启动 App。

## 当前下载状态

源码仓库已公开，所有 GitHub Release 均为草稿。`v0.2.0-preview.5` 也尚未发布，因此现在没有公开的 `releases/download/...` 下载端点。获准的维护者可登录后从 [Releases 页面](https://github.com/rexchen1803/wizard/releases)查看草稿；该页面是维护入口，不代表公开下载已开放，也不保证附件可用。若你没有权限读取所需附件，或固定文件不可用，请停止；不要发布 Release、改变仓库可见性或改用 `latest`。仓库公开不会自动发布草稿或开放其附件下载。

v0.2.0-preview.5 发布后，build41 安装包和清单的固定文件名及预期路径为：

| 文件 | 固定文件名 | 发布后的固定下载地址（当前尚不可用） |
| --- | --- | --- |
| Wizard Debian 包 | `wizard_0.2.0-20261112.41_iphoneos-arm.deb` | `https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.5/wizard_0.2.0-20261112.41_iphoneos-arm.deb` |
| 包清单 | `wizard_0.2.0-20261112.41_iphoneos-arm.deb.manifest.json` | `https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.5/wizard_0.2.0-20261112.41_iphoneos-arm.deb.manifest.json` |

只有在固定版本的 `.deb` 和同一版本清单均可从获准来源取得时才继续。使用清单中的 `artifact_sha256` 核对 `.deb`：macOS 可运行 `shasum -a 256 wizard_0.2.0-20261112.41_iphoneos-arm.deb`。版本、文件名或哈希不一致时停止，不混用其他版本的包与清单。打包脚本会为每次输出生成对应清单和哈希；本仓库没有硬编码可替代下载清单的 build41 `.deb` 哈希。

## 设备范围与前置条件

安装器只接受以下精确型号与 iOS 版本配对：

| 设备 | 型号标识 | iOS |
| --- | --- | --- |
| iPad 2 | `iPad2,4` | `9.3.5` |
| iPad 4 | `iPad3,4` | `10.3.3` |
| iPad Air | `iPad4,1` | `12.5.8` |

还必须具备 rootful 越狱环境、root 权限、可写且不是符号链接的 `/Applications`、Debian 包管理环境，以及 `ldid`、`uicache`、`killall`、`sysctl` 和 `sw_vers`。`uicache` 必须支持 `-p` 注册和 `-u` 取消注册。原版未越狱 iOS、rootless 越狱、iPhone，以及未列出的设备或系统版本都会被拒绝。不得通过改型号或系统版本绕过检查。

包结构与安装器的本机夹具预检不等于设备上的安装、签名、注册或启动验收。较早 build 在个别已准备设备上的记录见[兼容性表](COMPATIBILITY.md)；它们不证明 build41 的首次安装。当前 build41 的设备验收仍未完成。

## 安装预览包

确认上文所列固定文件在你的获准来源中可用后：

1. 下载 `wizard_0.2.0-20261112.41_iphoneos-arm.deb` 及其同名 `.manifest.json` 清单。草稿未公开时，不要把上述未来下载地址当作可用链接；维护者可从 [Releases 页面](https://github.com/rexchen1803/wizard/releases)打开草稿。若附件无法获取，停止。
2. 按清单中的 `artifact_sha256` 校验 `.deb`。只使用与该包配套的清单；不要改用 `latest`、别的 Release 或重新命名的包。
3. 在已授权的目标 iPad 上，通过 Filza 或 Cydia、Sileo、Zebra 支持的本地 `.deb` 安装流程安装。已获准的设备 root 终端也可运行：

   ```sh
   dpkg -i ./wizard_0.2.0-20261112.41_iphoneos-arm.deb
   ```

安装钩子先验证设备型号、系统、rootful 环境、包管理器、所需工具和 App 路径。安装器在设备上使用已有的 `ldid` 为未签名 App 执行 ad-hoc 签名，并用 `uicache` 注册 App。更新时它最多向 Wizard 发送一次 `TERM`，把原有 App 完整保留为 `WizardSystem.rollback-<build>-<UTC>.app`，再放入候选 App。首次安装没有旧 App 可作为回滚包。安装器不会启动 Wizard、重启设备或执行 respring。

安装包替换范围不包括 `/var/mobile/Media/iPadWizard/app`、Wizard 偏好设置或既有回滚目录。若签名、文件替换或注册失败，安装器会按实际分支恢复或保留候选、旧 App 和恢复目录。保留错误现场并报告原始错误；不要强制 respring、删除恢复目录或清理用户数据。安装成功只表示安装器完成，仍需由用户手动打开 App 并单独验收。

## 从源码构建

源码仓库已公开，可直接通过 HTTPS 克隆。构建需要 macOS、Apple Clang 和自行从 Apple 开发工具中取得的 iPhoneOS SDK；Apple SDK 不包含在仓库中。当前验证过的 SDK 是 iPhoneOS 9.3；较新 SDK 的 armv7 与旧 MediaPlayer 接口兼容性尚未验证。

```sh
git clone https://github.com/rexchen1803/wizard.git
cd wizard
IOS_SDK="/path/to/iPhoneOS9.3.sdk" ./scripts/build-ipad.sh --out /tmp/WizardSystem-build
python3 scripts/package-release.py \
  --app /tmp/WizardSystem-build/WizardSystem.app \
  --out /tmp/wizard_0.2.0-20261112.41_iphoneos-arm.deb
```

输出 App 目录、`.deb` 和相邻 manifest 必须尚不存在。打包器要求版本文件名与 App build 一致，核对 `armv7`、`arm64` 架构、bundle ID、资源和源指纹，并在本次生成的清单中写入 `artifact_sha256`。`--dry-run` 只输出包结构和哈希，不写包文件。构建和打包命令不会连接设备或执行安装。完整的[源码与开发指南](zh-CN/DEVELOPMENT.md#构建)说明了源码验证范围；[WizardPower 源码说明](../App/WizardPowerTweak/README.md)有独立构建入口，Wizard 安装包不会自动安装该插件。

## 可选 GTA VI 图库

图库和原始素材包也属于尚未公开的 `v0.2.0-preview.5` 草稿附件。当前没有公开下载端点。只有维护者或已获准的用户能从草稿取得附件时才可使用；无法获取时停止，不要发布 Release 或改变仓库可见性。

| 文件 | 内容 | 大小 | SHA-256 |
| --- | --- | ---: | --- |
| `wizard-gta6-gallery-20261112.zip` | 230 项图库目录、228 张图片、2 段视频及缩略图 | 258,253,713 bytes | `b8bd883b81a0a76086217ce3c27091d83b0b8261dcbabae49c88abb67aef3eba` |
| `gta6-original-materials-20261112.zip` | 343 张原始 JPEG、2 段 MKV、2 份 SRT | 755,809,316 bytes | `182cb83aaf463dc22004f750a4e51a2419ef50eb2da851aba9c6d456d89aea0b` |

这些固定文件的[本地清单](../assets/media/MANIFEST.json)记录预期大小与 SHA-256。发布后的固定路径如下，**当前尚不可用**：

```text
https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.5/wizard-gta6-gallery-20261112.zip
https://github.com/rexchen1803/wizard/releases/download/v0.2.0-preview.5/gta6-original-materials-20261112.zip
```

App 图库包仅在你另行选择并授权安装后使用。先完整备份设备上的 `/var/mobile/Media/iPadWizard/app`，再将 ZIP 中 `app/` 的内容合并到该目录；保留现有 `assets/user` 和偏好设置，不删除或替换整个 `app` 目录。若传输工具改写了新复制文件的权限，只修正这些新文件，不递归更改已有用户目录。重新打开 Wizard 后检查原壁纸、收藏、裁切、用户导入照片和分类。原始素材包用于收藏与制作，不是设备图库安装包。素材版权与署名见[素材说明](open-source/GTA6-MATERIALS.md)及[署名清单](../assets/media/ATTRIBUTION.md)；Rockstar 素材不适用 Wizard 的 MIT 代码许可。

## 回滚与卸载

更新后记录安装器打印的确切回滚目录。在设备上已获准的 root 终端中，将示例中的占位部分替换为安装器实际打印的完整路径：

```sh
/usr/lib/wizard-installer/install-wizard.sh rollback "/Applications/WizardSystem.rollback-<build>-<UTC>.app"
```

回滚会保留当前候选 App 为 `WizardSystem.failed-rollback-<UTC>.app`，恢复指定的 `WizardSystem.rollback-*` 或 `WizardSystem.uninstalled-*` 目录并重新注册；不会启动 App 或重启 SpringBoard。遇到失败时保留各目录并报告，不猜测删除或覆盖。

只有在任务明确要求卸载 Debian 包时，才通过包管理器卸载，或在获准的设备 root 终端运行：

```sh
dpkg -r com.rex.wizardsystem
```

卸载钩子只会注销 build 与当前包匹配的 Wizard App，并将完整 bundle 保留为 `WizardSystem.uninstalled-<build>-<UTC>.app`；如果已安装 App 的 build 不匹配，则保留该 App，但包管理器仍可能继续移除本包及其 helper。卸载不清除媒体、偏好设置和既有回滚目录。若要恢复被归档的 App，重新安装同一固定 `.deb` 取回 helper，再把真实的 `WizardSystem.uninstalled-*` 路径传给 `rollback`。清除个人媒体或偏好设置是独立操作，不属于普通卸载。

App bundle 内含已署名的 Vice City 默认壁纸；没有外部图库时也可显示。完整图库是可选附件。

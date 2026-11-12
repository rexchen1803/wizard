# 第三方素材与构建要求

**简体中文** · [English](../../THIRD_PARTY.md)

Wizard 自有代码采用根目录 [MIT License](../../LICENSE)。该许可不覆盖第三方代码、字体、图片、视频或其他素材；它们保留各自权利与条款。

## Google Material 图标路径

App 的部分矢量绘图路径来自 Google Material 图标，固定到 [`material-design-icons` revision `10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7`](https://github.com/google/material-design-icons/tree/10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7)，按 Apache 2.0 分发。[上游许可副本](../../licenses/Material-Icons-Apache-2.0.txt)和根目录 [NOTICE](../../NOTICE)保留署名与改动说明。

`IWMaterialPathForButton` 的35种变体对应33个上游 SVG，保留的路径使用固定版本数据。原游戏专用 Pet 和 Leaderboard 路径已移除。绘制由本地 Core Graphics 完成，不包含 Google SVG、字体或图片二进制；主题按钮保留自制三色绘制分支。逐项来源见[图标清单](../open-source/MATERIAL-ICONS.md)。

固定版本根目录有 `LICENSE`；对应 SVG 路径与上级目录中未找到独立 `NOTICE`、`COPYING` 或版权文件。保留路径于2026-11-12按此前核对清单复核，数据未变。这是来源记录，不构成法律许可结论。

## Apple SDK 与系统框架

设备构建使用自行提供的 iPhoneOS SDK，链接 UIKit、Foundation、AVFoundation、MediaPlayer、CoreMotion、CoreLocation、CoreMedia、CoreText、QuartzCore、CoreGraphics 与 CoreFoundation。仓库不含 Apple SDK、框架二进制或 SDK 头文件；请通过 Apple 开发工具获取并遵守其条款。

App 还会动态打开 `BackBoardServices`、`GraphicsServices` 与 `SpringBoardServices` 私有框架，用于显示和锁屏操作。构建保留 `dynamic_lookup`，编译成功不证明设备上的符号可用。媒体与偏好位于 `/var/mobile/Media` 和 `/var/mobile/Library/Preferences`，体现历史越狱/非沙盒部署假设。原版设备侧载尚未验证，见[开发指南](DEVELOPMENT.md)。

## 可选电源插件与 Theos

仓库包含 `WizardPowerTweak` 源码，但不含 Theos、Logos、第三方头文件、库或私有工作区工具链。历史工具链记录中的 Theos 为 GPL-3.0-or-later；选择使用 Theos 的构建者需自行获取并遵守其版本许可。主 App 构建不构建此插件。可选 `scripts/build-power.sh` 直接使用 Apple Clang，无需分发 Theos。插件注入、电源和运行兼容性需要单独验收。

## 导出范围

经过审查的源码导出排除 Apple SDK、第三方工具链、私有设备安装器、SSH 材料、连接日志、known-host 数据、设备状态、历史编译产物、完整原始媒体包、未核实权利的字体/图片，以及无关工作区内容。`assets/demo` 中的选定原生截图保留 Rockstar 署名，完整素材包单独保存在 Release 草稿中。导出报告分别记录代码许可与第三方排除项。预览版不承诺首次安装、实时天气或完整设备验收。

## 天气服务

可选天气适配器保留用于评估，实时 Open-Meteo 接入尚未验收。天气卡提供本地化署名入口与说明页，标注 Open-Meteo、[CC BY 4.0](https://open-meteo.com/en/licence)及 Wizard 的本地化和精简处理。此前 iPad 2/4 的合成夹具和原生卡片/详情检查仅适用于当时的构建；Air 的对应检查未完成。早期真实请求出现 TLS `-1202`，没有绕过系统信任。

Open-Meteo 的[服务条款](https://open-meteo.com/en/terms)将免费托管 API 限于非商业用途，并要求接受 CC BY 4.0 数据条款；[数据许可](https://open-meteo.com/en/licence)要求适当署名、许可链接和改动说明。商业托管服务另有订阅条款。2026-11-12已重新核对这两个页面；不据此声称未来部署已满足服务条件或取得法律许可。

## Rockstar Games GTA VI 素材

GTA VI 图片、视频、裁切、转码、缩略图与其他衍生内容归 Rockstar Games 及相关权利人。素材来源陈述由项目所有者提供，指向 Rockstar 的公开下载页面：[Artwork & Wallpapers](https://www.rockstargames.com/VI/media/artwork-wallpapers)、[媒体](https://www.rockstargames.com/VI/media)、[视频](https://www.rockstargames.com/VI/media/videos)。文件名清单核对不等于逐文件字节来源或再分发授权，公开下载也不将这些内容改为 MIT。

相关权利要求见 Rockstar 的[法律条款](https://www.rockstargames.com/legal/)与[版权内容发布政策](https://support.rockstargames.com/articles/7bNaeoMFTV0iUDGhStTXvz/policy-on-posting-copyrighted-rockstar-games-material)。项目署名不构成授权或官方背书。

当前图库包有228张图片、2段 GTA VI 预告片和相应缩略图，另有独立原始素材包；完整文件范围及字幕来源限制见[素材说明](../open-source/GTA6-MATERIALS.md)和[素材清单](../../assets/media/MANIFEST.json)。原始包中的两份 SRT 作者未经独立核实，不声称是 Rockstar 官方字幕。用户导入内容不归入这份 Rockstar 署名。

## 字体

App 的静态 `Anton-Regular.ttf` 保留原始字节，Copyright 2020 The Anton Project Authors，采用 [SIL OFL 1.1](../../App/Resources/Anton-OFL.txt)。来源固定到 [Google Fonts revision `cee74d7ca45d66d5c1878c828645c862f2788d2d`](https://github.com/google/fonts/tree/cee74d7ca45d66d5c1878c828645c862f2788d2d/ofl/anton)，SHA256 为 `a4ba3a92350ebb031da0cb47630ac49eb265082ca1bc0450442f4a83ab947cab`。字体与许可随 App 打包，独立于 MIT。README 的拉丁显示字使用同一字体。

README 的阅读文字和中文标题从 Noto Sans CJK SC Regular/Bold 转为轮廓，采用 [OFL 1.1](../../licenses/NotoSansCJK-OFL.txt)。Noto 字体仅为可选宣传图生成输入，不打入 App。固定来源、校验值与复现方法见[宣传图来源](../../assets/readme/SOURCES.md)。

## 默认壁纸与宣传图

`App/Resources/ViceCity.jpg` 是内置默认壁纸，来自所提供的 `ULTIMATE_EDITION_VICE_CITY_STYLE_01.jpg`。原图名称与校验值见[素材署名](../../assets/media/ATTRIBUTION.md)。README 和原生截图也包含已提供素材；这些内容与衍生图保留 Rockstar 及相关权利人版权，排除在 MIT 之外。不分发 Rockstar 专有字体。

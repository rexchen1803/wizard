**简体中文** · [繁體中文](../zh-TW/GTA6-MATERIALS.md) · [English](../en/GTA6-MATERIALS.md) · [日本語](../ja/GTA6-MATERIALS.md)

# GTA VI 素材来源与权利说明

GTA VI 图片、视频、截图及其缩略图、转码和裁切的版权属于 **Rockstar Games 与相应权利人**。这些素材与 Wizard 自有代码分开管理，不受项目 MIT License 授权。本项目与 Rockstar Games 没有隶属、赞助或认可关系。

## 分发状态与素材包

截至 2026-11-13，[v0.2.0-preview.5](https://github.com/rexchen1803/wizard/releases/tag/v0.2.0-preview.5) 已公开发布，以下图库和原始素材包均可免登录下载。清单中的 `download_url` 固定到该版本；下载后请核对大小和 SHA-256。

| 素材包 | 清单中的内容 | 预期用途 |
| --- | --- | --- |
| `wizard-gta6-gallery-20261112.zip` | 464 个文件：230 条图库目录项、228 张横向图片、2 段 MP4 预告片、230 张缩略图，共 460 个媒体引用。 | Wizard 可选图库。 |
| `gta6-original-materials-20261112.zip` | 350 个文件：343 张原始 JPEG、2 段 MKV 视频、2 份 SRT 字幕及包内说明文件。 | 原始素材归档与后续制作参考。 |

两个压缩包的字节数、SHA-256 和清单记录见[素材清单](../../assets/media/MANIFEST.json)。每包均包含逐文件清单、版权署名和用途说明。原始文件名保留；App 图库的分类、简短显示名和稳定 key 分开管理。两份 SRT 的作者来源尚未独立核实，不声称它们是 Rockstar 官方字幕。

素材来源核对、文件名匹配与内容分类记录不等于逐文件字节级来源证明，也不构成再分发许可。媒体包中的每个文件仍受相应权利约束。

## Rockstar 官方来源

项目所有者从 Rockstar 的公开媒体与下载页面整理了素材：

- [GTA VI Artwork & Wallpapers](https://www.rockstargames.com/VI/media/artwork-wallpapers)
- [GTA VI Media](https://www.rockstargames.com/VI/media)
- [GTA VI Videos](https://www.rockstargames.com/VI/media/videos)
- [Rockstar Games Legal Terms](https://www.rockstargames.com/legal/)

本项目整理的源文件记录包含 27 组壁纸构图及其 142 个尺寸或标志版本、138 张游戏截图、51 张 Ultimate Edition 图片和 12 张 Vintage Vice City Pack 图片。图库为每组壁纸选择一张横向图片，并保留全部截图与内容包图片。Rockstar 网站内容可能更新；此处描述的具体包范围以[素材清单](../../assets/media/MANIFEST.json)和包内逐文件清单为准。

## 仓库演示图与许可范围

仓库的 [assets/demo](../../assets/demo/README.md) 说明了随代码保存的 App 截图来源：当前八张 `*-miami.jpg` 与 `clock-font-system.jpg` 是 build `20261112.41` 在 iPad 第 8 代、iOS 18 模拟器中的原生截图；`*-ipad2.png` 是 build `20261111.36` 的早期实体设备截图。截图里的 GTA VI 画面仍属于 Rockstar Games 与相应权利人，不适用 Wizard 的 MIT 代码许可。

媒体包不包含用户照片、个人偏好、设备备份、连接信息、F1 视频、历史游戏音频、字体或 Apple SDK。安装和运行时条件见[安装指南](../INSTALL.md)，统一署名见 [ATTRIBUTION.md](../../assets/media/ATTRIBUTION.md)。

## App 默认图与宣传素材

当前 App 构建包含 `App/Resources/ViceCity.jpg`，来源文件为 `ULTIMATE_EDITION_VICE_CITY_STYLE_01.jpg`。该图为 3840 × 2160 像素，仓库中的该文件与来源字节一致；SHA-256 为 `c255874fee509eae0baa6f546861e483ec0b32efbfe8d013ec36888013d923c9`。App 只在没有外部图库目录时使用它作为默认画面。README 宣传图和原生截图也使用了经署名的 Rockstar 素材。相关图片与衍生图均不受 MIT 许可。App 内另有 SIL OFL 字体；仓库不分发 Rockstar 字体文件。

## 相关记录

- [素材清单与校验值](../../assets/media/MANIFEST.json)
- [统一素材署名](../../assets/media/ATTRIBUTION.md)
- [演示截图来源与元数据](../../assets/demo/README.md)
- [第三方许可与服务条款](../../THIRD_PARTY.md)

# 演示截图来源

**简体中文** · [繁體中文](../../docs/zh-TW/CAPTURES.md) · [English](README.en.md) · [日本語](../../docs/ja/CAPTURES.md)

## 当前 Miami 预览

`*-miami.jpg` 来自 build **20261112.41** 在 **iPad（第 8 代）模拟器 / iOS 18.0** 中的原生 UIKit 渲染。原始截图为 2160 × 1620 PNG；网页版本保持同样像素尺寸，使用 JPEG quality 85 编码，未合成、添加或重绘任何 App 界面。原始 PNG 的 SHA256、网页图片校验值、场景命令和源码指纹在 [CAPTURE-METADATA.json](CAPTURE-METADATA.json)。

- [主屏](home-miami.jpg)：未安装外部目录时的内置 Vice City 默认图。
- [图库](gallery-miami.jpg)、[分类](categories-miami.jpg)：演示目录由 230 项素材包加上所选默认图组成，共 231 项。未加入用户照片。
- [主菜单](menu-miami.jpg)、[设置](settings-miami.jpg)、[主题](themes-miami.jpg)。
- [时钟编辑](clock-edit-miami.jpg)、[日历](calendar-miami.jpg)。

截图构建和 `armv7 + arm64` 设备构建绑定同一份源码与资源；模拟器使用独立 App 标识和沙盒媒体路径。构建入口及复现方式见[原生模拟器预览](../../docs/open-source/README.md#native-simulator-preview)。模拟器检查不替代旧款实体 iPad 的运行验收。

## 更多布局与生活场景

以下六张是 build **20261112.41** 在 **iPad（第 8 代）模拟器 / iOS 18.0** 中截取的原生画面，PNG 未修改：[落日海报](screens/sunset-poster.png)、[岛屿极简](screens/island-minimal.png)、[夜城](screens/night-city.png)、[城市日历](screens/city-calendar.png)、[绿意静居](screens/green-retreat.png)、[棕榈车道](screens/palm-drive.png)。尺寸、校验值和模拟器来源见[截图元数据](screens/CAPTURE-METADATA.json)。

生活场景：[网站书房](environments/website-study.jpg)、[日光书桌](environments/daylight-desk.jpg)、[亚麻床头](environments/linen-bedside.jpg)、[暮色边柜](environments/dusk-console.jpg)。网站书房沿用用户提供的场景，并以当前 App 截图替换原有屏幕；其余三幅为生成的环境插画。每幅中的 App 画面均按固定位置直接投影自上述原始截图，未虚构或重绘界面。场景中的 iPad 2、iPad 4 与初代 iPad Air 外形仅作示意，不代表这些实体设备运行了 build 41，也不构成兼容性或实机验收证据。场景构图与素材来源见[场景记录](environments/SCENES.json)。

## 字体来源

当前构建把静态开源字体 `Anton-Regular.ttf` 和 OFL 1.1 许可一起打入 App。截图元数据同时记录真实时钟字体名 `Anton-Regular`、字体文件 SHA256 和字体是否来自 App 包，避免把模拟器的系统字体回退当成旧系统字体一致性证据。中文控件使用系统字体。旧 source36 实机图保留其当时的外观。

长按时间，在“时间字体”中选择“海报 / 系统”。海报使用内置 Anton，系统使用 iOS 等宽数字；完成保存，取消恢复。新增[系统字体编辑实截](clock-font-system.jpg)展示真实选择器。

## 保留的旧版实机宣传图

以下 source36 原始 PNG 保持原像素，来自 iPad2,4 / iOS9.3.5，拍摄于 2026-11-11：

- [旧版主屏](home-ipad2.png)
- [旧版图库](gallery-ipad2.png)
- [旧版分类](categories-ipad2.png)

它们是旧版真实设备记录，不作为当前 Miami 构建的真机验收。

## 署名

GTA VI 图片和截图中的相应素材版权属于 Rockstar Games 与相关权利人；这些演示图片不适用 Wizard 的 MIT 源码许可。具体原图和权利范围见[素材署名](../media/ATTRIBUTION.md)。

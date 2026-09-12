# README 动画

`images/settings-preview.gif` 为 680 × 430、150 帧、10 秒循环 GIF，便于 README 直接展示。

导出器复用 `GlassMetalView.shader`、`HingeDemoMotion` 和 `EffectAngle`，以 90° 为起始模糊角度。设备外观裁自工程现有 Apple 产品图，屏幕内容裁自 Apple 官方 macOS Tahoe 26 桌面示例（包含菜单栏、Dock、小组件和 Music 窗口），来源与版权见 [素材说明](../Assets/SOURCES.md)。不读取屏幕录制权限，不捕获个人桌面。Core Image 用于离线合成机身透视，因此这不是 SwiftUI 设置窗口的逐帧录屏。

在支持 Metal 的 macOS 桌面环境中，从仓库根目录运行：

```sh
mkdir -p .build/ModuleCache
swiftc -module-cache-path .build/ModuleCache -parse-as-library \
  -framework AppKit -framework SwiftUI -framework MetalKit -framework CoreImage \
  Sources/GlassRenderer.swift Sources/EffectAngle.swift Sources/HingeDemoMotion.swift \
  Tools/ExportPreview.swift -o .build/ExportPreview
.build/ExportPreview
```

输出覆盖 `docs/images/settings-preview.gif`；两个用于外观检查的关键帧输出到系统临时目录。

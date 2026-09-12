# 本地资源优化

2026-09-11 优化前采样：应用 CPU 平均约 21.1%（100% 为一个核心），内存 254–292 MB。采样未区分清晰待机与模糊显示，不作为严格的前后对照。

本次改动：

- 清晰待机只保留最新桌面帧，不执行纹理上传、mipmap 生成或覆盖层绘制；进入效果区域后处理最新帧。
- 控制定时器由 60 Hz 降至 30 Hz，与铰链传感器匹配；Metal 动画仍使用 60 Hz。
- 角度和参数未变化时不唤醒已暂停的渲染器；传感器读数未变化时不发布界面刷新。
- 只在窗口显示状态变化时隐藏窗口，菜单关闭时不刷新捕获计数，取消周期性状态日志。
- 完全清晰的着色路径从 24 次模糊采样简化为一次图像采样。

桌面捕获仍保持 30 fps，以保留触发响应速度。暂停、停止和重新触发后的实际效果，以及新版 CPU、GPU 和内存变化需要在有录屏权限的会话中复测；不能由上述代码改动推算降幅。

验证命令（在工程目录执行，渲染测试需要本机 Metal 访问）：

```sh
./build.sh
swiftc -module-cache-path .build/ModuleCache -parse-as-library -framework AppKit -framework SwiftUI -framework MetalKit Sources/GlassRenderer.swift Tests/RendererActivityTests.swift -o .build/RendererActivityTests
.build/RendererActivityTests
```

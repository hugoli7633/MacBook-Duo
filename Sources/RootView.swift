import SwiftUI
import AppKit

struct RootView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Group {
            switch model.page {
            case .setup: SetupView(model: model, loginItem: model.loginItem)
            case .test: TestView(model: model, sensor: model.sensor).preferredColorScheme(.dark)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SetupView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var loginItem: LoginItemController
    @State private var advanced = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "macbook")
                        .font(.system(size: 28, weight: .medium)).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MacBook Duo").font(.title2.weight(.semibold))
                        Text("随屏幕开合，渐入模糊。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(model.globalRunning ? "已启用" : "未启用")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(model.globalRunning ? Color.blue : Color.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.quaternary, in: Capsule())
                }

                HingeDemoView(onset: model.blurStartAngle, desktop: model.desktopPreview)

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("开始模糊角度").fontWeight(.medium)
                            Spacer()
                            Text("\(Int(model.blurStartAngle))°")
                                .font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.blue)
                        }
                        Slider(value: $model.blurStartAngle, in: 1...model.openAngle, step: 1)
                            .accessibilityLabel("开始模糊角度")
                        Text("低于此角度开始模糊，展开后恢复清晰。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(16)
                    Divider().padding(.leading, 16)
                    HStack {
                        Text("登录后自动启动")
                        Spacer()
                        Toggle("登录后自动启动", isOn: Binding(
                            get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                            .disabled(loginItem.updating)
                    }.padding(16)
                    if loginItem.needsApproval || loginItem.message.contains("失败") {
                        HStack {
                            Text(loginItem.message).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("系统设置", action: loginItem.openSettings)
                        }.padding([.horizontal, .bottom], 16)
                    }
                    Divider().padding(.leading, 16)
                    HStack {
                        Text("屏幕录制权限")
                        Spacer()
                        Button("管理权限", action: model.openScreenRecordingSettings)
                        Button("授权后重启", action: model.restartAfterPermission)
                            .disabled(model.restarting)
                    }.padding(16)
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.3)))

                HStack {
                    if model.globalRunning {
                        Button("停止功能") { model.stopGlobal?() }
                    }
                    Spacer()
                    Button(model.globalRunning ? "完成，后台运行" : "启用效果") {
                        if model.globalRunning { model.hideControls?() } else { model.startGlobal?() }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.permissionsPreparing)
                }
                Text(model.globalStatus)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                DisclosureGroup("高级与截图测试", isExpanded: $advanced) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("展开终点  \(Int(model.openAngle))°")
                            Spacer()
                            Button("校准当前角度") { model.saveOpenAngle() }
                        }
                        Text("蓝色图标表示效果生效；白色表示清晰待机或未启用。⌘⇧Esc 紧急停止。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("导入截图", action: model.importScreenshot)
                            Button("截图测试", action: model.startTest).disabled(model.desktopImage == nil)
                            Spacer()
                            Button("实机预览 8 秒") { model.previewGlobal?() }
                                .disabled(model.permissionsPreparing)
                        }
                    }.padding(.top, 12)
                }
                .font(.subheadline)
            }
            .padding(24)
            .frame(maxWidth: 660)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct BlurStartControl: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("开始模糊角度")
                Slider(value: $model.blurStartAngle, in: 1...model.openAngle, step: 1)
                    .accessibilityLabel("开始模糊角度")
                Text("\(Int(model.blurStartAngle.rounded()))°")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            Text("低于此角度开始模糊，数值越小，需要合得越低。设置自动保存。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
    }
}

private struct TestView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var sensor: LidAngleSensor
    @State private var strength = 1.0
    @State private var frost = 0.09
    @State private var distance = 2.4

    private var angle: Double {
        model.useSensor && sensor.isAvailable ? sensor.angle : model.simulatedAngle
    }

    var body: some View {
        ZStack {
            if let image = model.desktopImage {
                GlassSurface(image: image, tilt: model.showOriginal ? 0 : 80 * EffectAngle.progress(angle: angle, onset: model.blurStartAngle, strength: strength),
                             frost: frost, distance: distance)
                    .ignoresSafeArea()
            }
            if !model.controlsHidden {
                VStack {
                    HStack {
                        Button("返回", action: model.returnToSetup)
                        Spacer()
                        Text("MACBOOK DUO · 调试设置").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button("退出软件") { NSApp.terminate(nil) }
                        Button("隐藏 / 恢复 · ⌘H") { model.controlsHidden.toggle() }
                    }
                    .buttonStyle(FloatingControlStyle())
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    Spacer()
                    VStack(spacing: 12) {
                        HStack {
                            Circle().fill(model.useSensor && sensor.isAvailable ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text("\(Int(angle.rounded()))°").monospacedDigit()
                            Text("0–\(Int(model.openAngle.rounded()))°").foregroundStyle(.secondary)
                            Spacer()
                            Toggle("原图对比 ⌘B", isOn: $model.showOriginal).toggleStyle(.checkbox)
                            Button("保存展开终点 ⌘K") { model.saveOpenAngle() }
                        }
                        HStack {
                            if sensor.isAvailable {
                                Toggle("实时铰链", isOn: $model.useSensor).toggleStyle(.switch).controlSize(.small)
                            }
                            Spacer()
                            Text(model.calibrationMessage.isEmpty ? "将屏幕打开至舒适角度，保存为终点" : model.calibrationMessage).foregroundStyle(.secondary)
                        }
                        if !model.useSensor || !sensor.isAvailable {
                            HStack {
                                Text("模拟角度").frame(width: 64, alignment: .leading)
                                Slider(value: $model.simulatedAngle, in: 0...180)
                            }
                        }
                        BlurStartControl(model: model)
                        HStack {
                            Text("深度强度").frame(width: 64, alignment: .leading)
                            Slider(value: $strength, in: 0.5...2)
                            Text(String(format: "%.1f×", strength)).frame(width: 35)
                            Text("磨砂")
                            Slider(value: $frost, in: 0...0.18).frame(width: 100)
                        }
                        Text("⌘H 隐藏 / 恢复 · Esc 显示控制 · ⌘K 保存终点 · ⌘Q 退出")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                    .padding(16)
                    .frame(width: 610)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.2), lineWidth: 0.7) }
                    .padding(.bottom, 20)
                }
            }
        }
        .background(.black)
        .focusable()
        .focusEffectDisabled()
    }
}

private struct FloatingControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.18), lineWidth: 0.7) }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 7)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

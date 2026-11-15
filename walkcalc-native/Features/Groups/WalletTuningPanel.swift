#if DEBUG
import SwiftUI
import UIKit

private enum WalletControlSection: String, CaseIterable, Identifiable {
    case layout = "卡包"
    case motion = "动画"
    case haptics = "触感"
    case glass = "玻璃"
    case color = "色彩"
    case text = "文字"
    var id: Self { self }
}

struct WalletTuningPanel: View {
    @Binding var appearance: WalletAppearance
    @Environment(\.colorScheme) private var colorScheme
    @State private var controlsExpanded = true
    @State private var controlSection = WalletControlSection.layout
    @State private var copiedParameters = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    controlsExpanded.toggle()
                } label: {
                    Label("卡包调节", systemImage: controlsExpanded ? "chevron.down" : "chevron.up")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                Spacer()
                Button("重置") {
                    var defaults = WalletAppearance(isDark: colorScheme == .dark)
                    defaults.palette = appearance.palette
                    appearance = defaults
                }
                    .font(.subheadline)
            }
            if controlsExpanded {
                Picker("调节类别", selection: $controlSection) {
                    ForEach(WalletControlSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                ScrollView {
                    VStack(spacing: 2) {
                        switch controlSection {
                        case .layout: layoutControls
                        case .motion: motionControls
                        case .haptics: hapticControls
                        case .glass: materialControls
                        case .color: colorControls
                        case .text: textControls
                        }
                    }
                }
                .frame(height: 204)
                HStack {
                    Text(colorScheme == .dark ? "深色参数自动保存" : "浅色参数自动保存")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(copiedParameters ? "已复制" : "复制参数") {
                        UIPasteboard.general.string = appearance.parameterSummary
                        copiedParameters = true
                    }
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(SoftLedgerTheme.paper)
        .onChange(of: appearance) { _, _ in copiedParameters = false }
    }

    private var layoutControls: some View {
        Group {
            adjustment("顶部下移", value: $appearance.backingOffset, range: -80...100,
                       display: "\(Int(appearance.backingOffset)) pt")
            note("黑色底座从卡叠顶部向下偏移；卡片增多时，底座随整体高度增长。")
            adjustment("叠放间距", value: $appearance.exposure, range: 28...72,
                       display: "\(Int(appearance.exposure)) pt")
            adjustment("间距递减", value: $appearance.spacingDecay, range: 0...0.5,
                       display: decimal(appearance.spacingDecay))
            note("间距按缓慢的反比例曲线收紧；0 保持原间距。")
            adjustment("左右留边", value: $appearance.cardInset, range: 18...48,
                       display: "\(Int(appearance.cardInset)) pt")
            adjustment("倾斜幅度", value: $appearance.tilt, range: 0...2,
                       display: appearance.tilt.formatted(.number.precision(.fractionLength(2))) + "×")
            adjustment("倾斜递减", value: $appearance.tiltDecay, range: 0...2,
                       display: decimal(appearance.tiltDecay))
            note("倾斜按指数曲线快速减小；值越大越快变平，0 关闭递减。单张不倾斜。")
            adjustment("左右错落", value: $appearance.spread, range: 0...3,
                       display: appearance.spread.formatted(.number.precision(.fractionLength(2))) + "×")
            Text("间距越小越紧凑；底座偏移为正时向下移动。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
    }

    private var motionControls: some View {
        VStack(spacing: 8) {
            Toggle("弹簧响应", isOn: $appearance.motion.springEnabled)
            if appearance.motion.springEnabled {
                adjustment("回弹强度", value: $appearance.motion.bounce, range: 0...0.5,
                           display: percent(appearance.motion.bounce))
                note("越大越有弹性，落位后会越位并衰减回弹；0% 仍是弹簧响应，只是不越位。")
            } else {
                Picker("补位缓动", selection: $appearance.motion.easing) {
                    Text("利落抽卡").tag(WalletMotionEasing.snappy)
                    Text("快速起步 · 缓出").tag(WalletMotionEasing.easeOut)
                    Text("缓入缓出").tag(WalletMotionEasing.easeInOut)
                    Text("匀速进度").tag(WalletMotionEasing.linear)
                    Text("自定义贝塞尔").tag(WalletMotionEasing.custom)
                }
                .pickerStyle(.menu)
            }
            adjustment(appearance.motion.springEnabled ? "响应时长" : "切换时长",
                       value: $appearance.motion.duration, range: 0.18...1.2,
                       display: seconds(appearance.motion.duration))
            if appearance.motion.springEnabled {
                note("响应时长控制主要动作的快慢；弹簧衰减至静止可能更久。")
            }
            adjustment("距离减速曲线", value: $appearance.motion.distanceResponse, range: 0...1,
                       display: decimal(appearance.motion.distanceResponse))
            adjustment("远距离加时上限", value: $appearance.motion.distanceExtraDuration, range: 0...1.5,
                       display: percent(appearance.motion.distanceExtraDuration))
            note("相邻卡片保持基础时长；更远的卡片按实际间距逐渐加时并趋于上限。曲线越大越早放慢，设为 0 恢复固定时长。")
            adjustment("向右抽出", value: $appearance.motion.horizontal, range: -60...80,
                       display: "\(Int(appearance.motion.horizontal)) pt")
            adjustment("向上抽出", value: $appearance.motion.lift, range: 0...120,
                       display: "\(Int(appearance.motion.lift)) pt")
            adjustment("抽出倾斜", value: $appearance.motion.rotation, range: -15...15,
                       display: appearance.motion.rotation.formatted(.number.precision(.fractionLength(1))) + "°")
            adjustment("抽出放大", value: $appearance.motion.scale, range: 0...0.12,
                       display: percent(appearance.motion.scale))
            adjustment("抽出峰值", value: $appearance.motion.peak, range: 0.15...0.65,
                       display: percent(appearance.motion.peak))
            adjustment("补位时机", value: $appearance.motion.slotDelay, range: 0...0.6,
                       display: percent(appearance.motion.slotDelay))
            adjustment("遮罩恢复时机", value: $appearance.motion.maskRestoreFraction, range: 0.5...1,
                       display: percent(appearance.motion.maskRestoreFraction))
            adjustment("遮罩移除时长", value: $appearance.motion.maskOpenDuration, range: 0...0.5,
                       display: seconds(appearance.motion.maskOpenDuration))
            adjustment("遮罩恢复时长", value: $appearance.motion.maskFadeDuration, range: 0.04...0.6,
                       display: seconds(appearance.motion.maskFadeDuration))
            adjustment("遮罩起点", value: $appearance.maskStartFraction, range: 0...0.9,
                       display: percent(appearance.maskStartFraction))
            note("起点从玻璃顶部向下计算，默认 67%；上方允许卡片溢出。恢复时机不变，移除和恢复时长独立控制淡变速度。")
            adjustment("金额时长", value: $appearance.motion.amountDuration, range: 0.15...0.8,
                       display: seconds(appearance.motion.amountDuration))
            adjustment("拖拽范围", value: $appearance.motion.dragRange, range: 0...64,
                       display: "\(Int(appearance.motion.dragRange)) pt")
            adjustment("回位时长", value: $appearance.motion.dragReturnDuration, range: 0.12...0.6,
                       display: seconds(appearance.motion.dragReturnDuration))
            adjustment("回位弹性", value: $appearance.motion.dragBounce, range: 0...0.4,
                       display: percent(appearance.motion.dragBounce))
            note("拖拽保持原层级，只跟手移动，松手回原位；0 pt 关闭拖拽，点击才会切换卡片。")
            note("峰值越小，越早抽出再落下；补位时机越小，其他卡片越早让位。百分比为主要动作时长的比例；点击会立即开始抽出。负的右移或倾斜值会反向。")
            if !appearance.motion.springEnabled && appearance.motion.easing == .custom {
                adjustment("控制点 X1", value: $appearance.motion.x1, range: 0...1,
                           display: decimal(appearance.motion.x1))
                adjustment("控制点 Y1", value: $appearance.motion.y1, range: 0...1,
                           display: decimal(appearance.motion.y1))
                adjustment("控制点 X2", value: $appearance.motion.x2, range: 0...1,
                           display: decimal(appearance.motion.x2))
                adjustment("控制点 Y2", value: $appearance.motion.y2, range: 0...1,
                           display: decimal(appearance.motion.y2))
                note("X 控制时间，Y 控制补位进度；抽出与回落使用连续关键帧。")
            }
            Button("仅重置动画") { appearance.motion = WalletMotion() }
            note("调整后点击上方任意卡片查看效果；动画参数会一起保存和复制。")
        }
        .font(.caption)
    }

    private var hapticControls: some View {
        VStack(spacing: 10) {
            Toggle("卡片触感", isOn: $appearance.motion.hapticsEnabled)
            VStack(spacing: 8) {
                adjustment("拿起强度", value: $appearance.motion.selectionHaptic, range: 0...1,
                           display: percent(appearance.motion.selectionHaptic))
                note("手指按住卡片时立即轻震，准备拖动也会触发；不等待点击松手或动画开始。")
                adjustment("落位强度", value: $appearance.motion.landingHaptic, range: 0...1,
                           display: percent(appearance.motion.landingHaptic))
                note("切换落位或拖拽回位时加重一次；连续操作会取消旧的落位反馈。0% 可单独关闭一段触感，需在真机上感受。")
            }
            .disabled(!appearance.motion.hapticsEnabled)
        }
        .font(.caption)
    }

    private func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    private func seconds(_ value: Double) -> String { decimal(value) + " s" }

    private var materialControls: some View {
        VStack(spacing: 8) {
            Toggle("原生玻璃基准", isOn: $appearance.nativeGlassOnly)
                .disabled(reduceTransparency)
            if appearance.nativeGlassOnly {
                note("直接使用系统常规 Liquid Glass：无染色、无额外模糊、无仿制边光。关闭此项可对比之前的调节，旧参数会保留。")
            }
            adjustment("玻璃高度", value: $appearance.glassHeightRatio, range: 0.55...1.15,
                       display: percent(appearance.glassHeightRatio))
            Toggle("触摸玻璃响应", isOn: $appearance.interactiveGlass)
                .disabled(reduceTransparency)
            if !appearance.nativeGlassOnly {
                VStack(spacing: 8) {
                    Picker("玻璃材质", selection: $appearance.regularGlass) {
                        Text("原生清透").tag(false)
                        Text("原生常规").tag(true)
                    }
                    .pickerStyle(.segmented)
                    adjustment("底层压暗", value: $appearance.tint, range: 0...0.8,
                               display: percent(appearance.tint))
                    ColorPicker("玻璃染色", selection: colorBinding(\.glassTint), supportsOpacity: false)
                    adjustment("染色强度", value: $appearance.glassTintAmount, range: 0...1,
                               display: percent(appearance.glassTintAmount))
                    adjustment("附加边光", value: $appearance.edgeHighlight, range: 0...1,
                               display: percent(appearance.edgeHighlight))
                    Toggle("额外雾化层", isOn: $appearance.extraFrost)
                    if appearance.extraFrost {
                        adjustment("雾层通透", value: $appearance.clarity, range: 0...1,
                                   display: percent(appearance.clarity))
                        adjustment("附加模糊", value: $appearance.blur, range: 0...40,
                                   display: "\(Int(appearance.blur)) pt")
                    }
                    note("额外雾化会先模糊背景副本，弱化原始细节；这些附加处理不是系统折射参数。")
                }
                .disabled(reduceTransparency)
            }
            if reduceTransparency { note("系统已开启降低透明度，玻璃显示为不透明底色。") }
            ColorPicker("卡套底色", selection: colorBinding(\.backingColor), supportsOpacity: false)
        }
        .font(.caption)
    }

    private var colorControls: some View {
        VStack(spacing: 8) {
            NavigationLink {
                WalletPaletteEditor()
            } label: {
                Text("Color Palette (\(appearance.palette.count))")
            }
            adjustment("双色差异", value: $appearance.colorSeparation, range: 0...1,
                       display: percent(appearance.colorSeparation))
            note("0% 为同色，100% 保留 A / B 的完整差异。以下滑块作用于所有配色。")
            adjustment("色彩浓度", value: $appearance.saturation, range: 0...1.8,
                       display: percent(appearance.saturation))
            adjustment("明度偏移", value: $appearance.brightness, range: -0.5...0.3,
                       display: percent(appearance.brightness))
            adjustment("色相偏移", value: $appearance.hueShift, range: -180...180,
                       display: "\(Int(appearance.hueShift))°")
            adjustment("辅色占比", value: $appearance.colorBalance, range: 0...1,
                       display: percent(appearance.colorBalance))
            adjustment("过渡柔和", value: $appearance.gradientSoftness, range: 0...1,
                       display: percent(appearance.gradientSoftness))
            adjustment("流动形态", value: $appearance.flow, range: 0...1.6,
                       display: appearance.flow.formatted(.number.precision(.fractionLength(2))))
        }
        .font(.caption)
    }

    private var textControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("卡片上的币种与金额")
            inkPicker("卡片文字", selection: $appearance.cardInkMode)
            if appearance.cardInkMode == .custom {
                ColorPicker("卡片文字颜色", selection: colorBinding(\.cardInkColor), supportsOpacity: false)
            }
            Text("玻璃区域的金额与提示")
            inkPicker("玻璃文字", selection: $appearance.glassInkMode)
            if appearance.glassInkMode == .custom {
                ColorPicker("玻璃文字颜色", selection: colorBinding(\.glassInkColor), supportsOpacity: false)
            }
            note("自动模式按调整后的底色选择同色系文字，并比较深浅对比度；副标题使用同色的次级透明度。")
        }
        .font(.caption)
    }

    private func inkPicker(_ title: String, selection: Binding<WalletInkMode>) -> some View {
        Picker(title, selection: selection) {
            Text("自动").tag(WalletInkMode.automatic)
            Text("深色").tag(WalletInkMode.dark)
            Text("浅色").tag(WalletInkMode.light)
            Text("自选").tag(WalletInkMode.custom)
        }
        .pickerStyle(.segmented)
    }

    private func colorBinding(_ path: WritableKeyPath<WalletAppearance, WalletRGB>) -> Binding<Color> {
        Binding(get: { appearance[keyPath: path].color },
                set: { appearance[keyPath: path] = WalletRGB(pickerColor: $0) })
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                            display: String) -> some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 62, alignment: .leading)
            Slider(value: value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue(display)
            Text(display)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
        }
        .font(.caption)
    }
}

private extension WalletRGB {
    init(pickerColor: Color) {
        let cgColor = UIColor(pickerColor).cgColor.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
        let components = cgColor?.components ?? [0, 0, 0, 1]
        self.init(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}

// Appearance override is scoped to the tuning sheet / Canvas, never persisted as an app setting.
struct WalletPreviewAppearance: ViewModifier {
    @State private var mode = 0
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(mode == 0 ? nil : mode == 1 ? .light : .dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("预览外观", selection: $mode) {
                            Text("跟随系统").tag(0)
                            Text("浅色").tag(1)
                            Text("深色").tag(2)
                        }
                    } label: {
                        Image(systemName: "circle.lefthalf.filled")
                    }
                    .accessibilityLabel("切换预览深浅色")
                }
            }
    }
}
#endif

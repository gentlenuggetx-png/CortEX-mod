import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit

/// 縦リーダーの自動スクロール。
/// SwiftUI ScrollView の裏にある UIScrollView を CADisplayLink で直接動かす
/// (.scrollPosition / ScrollViewReader は 1 ページ単位のジャンプしかできず、等速スクロールにならない)。
/// ユーザーが指で触っている間は送りを止め、離すとその位置から再開する。
@MainActor
final class AutoScrollController: ObservableObject {
    /// 速度段階 (pt/秒)
    static let speeds: [Double] = [20, 35, 50, 75, 100, 150, 200, 300]
    private static let speedKey = "autoScrollSpeedLevel"

    @Published var isRunning = false {
        didSet {
            guard isRunning != oldValue else { return }
            isRunning ? start() : stop()
        }
    }
    @Published var speedLevel: Int {
        didSet { UserDefaults.standard.set(speedLevel, forKey: Self.speedKey) }
    }

    weak var scrollView: UIScrollView?
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    /// 開始前の idle timer 状態 (DL 画面など他所で無効化済みの場合に勝手に戻さない)
    private var idleTimerWasDisabled = false

    init() {
        let saved = UserDefaults.standard.object(forKey: Self.speedKey) as? Int ?? 3
        speedLevel = min(max(saved, 0), Self.speeds.count - 1)
    }

    var pointsPerSecond: Double { Self.speeds[speedLevel] }
    var canSpeedUp: Bool { speedLevel < Self.speeds.count - 1 }
    var canSlowDown: Bool { speedLevel > 0 }

    func speedUp() { if canSpeedUp { speedLevel += 1 } }
    func slowDown() { if canSlowDown { speedLevel -= 1 } }
    func toggle() { isRunning.toggle() }

    private func start() {
        lastTimestamp = 0
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        LogManager.shared.log("AutoScroll", "start speed=\(pointsPerSecond)pt/s attached=\(scrollView != nil)")
    }

    private func stop() {
        link?.invalidate()
        link = nil
        if !idleTimerWasDisabled {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        LogManager.shared.log("AutoScroll", "stop")
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let dt = lastTimestamp == 0 ? 0 : link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        guard let sv = scrollView, sv.window != nil else { return }
        // 指で触っている / 慣性スクロール中 / ズーム中は送らない (離せば再開)
        if sv.isTracking || sv.isDragging || sv.isDecelerating || sv.isZooming { return }

        let maxY = sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom
        guard maxY > 0 else { return }
        // バックグラウンド復帰などで dt が跳ねても一気に飛ばない
        var y = sv.contentOffset.y + CGFloat(pointsPerSecond * min(dt, 0.1))
        if y >= maxY {
            y = maxY
            isRunning = false
        }
        sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: y), animated: false)
    }
}

/// CADisplayLink は target を強参照するので、controller を直接渡すと循環参照になる
private final class DisplayLinkProxy: NSObject {
    weak var owner: AutoScrollController?
    init(_ owner: AutoScrollController) { self.owner = owner }

    @objc func tick(_ link: CADisplayLink) {
        guard let owner else { link.invalidate(); return }
        MainActor.assumeIsolated { owner.tick(link) }
    }
}

/// ScrollView のコンテンツ内に置くと、祖先の UIScrollView を controller に渡す
struct AutoScrollAttacher: UIViewRepresentable {
    let controller: AutoScrollController

    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.isUserInteractionEnabled = false
        view.onFound = { [weak controller] sv in controller?.scrollView = sv }
        return view
    }

    func updateUIView(_ uiView: FinderView, context: Context) {
        uiView.resolve()
    }

    final class FinderView: UIView {
        var onFound: ((UIScrollView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            resolve()
        }

        func resolve() {
            DispatchQueue.main.async { [weak self] in
                var current = self?.superview
                while let view = current {
                    if let sv = view as? UIScrollView {
                        self?.onFound?(sv)
                        return
                    }
                    current = view.superview
                }
            }
        }
    }
}

/// 右下の自動スクロール操作ボタン。
/// コントロール表示中は速度 −/+ も出し、非表示中は再生/停止だけの小さなボタンになる。
struct AutoScrollButton: View {
    @ObservedObject var controller: AutoScrollController
    let expanded: Bool

    var body: some View {
        HStack(spacing: 14) {
            if expanded {
                Button { controller.slowDown() } label: {
                    Image(systemName: "tortoise.fill")
                }
                .disabled(!controller.canSlowDown)

                Text("\(controller.speedLevel + 1)")
                    .font(.subheadline.monospacedDigit().bold())
                    .frame(minWidth: 14)

                Button { controller.speedUp() } label: {
                    Image(systemName: "hare.fill")
                }
                .disabled(!controller.canSpeedUp)
            }

            Button { controller.toggle() } label: {
                Image(systemName: controller.isRunning ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 28, height: 28)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, expanded ? 16 : 10)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(expanded ? 0.9 : 0.5))
        .clipShape(Capsule())
        .opacity(expanded || controller.isRunning ? 1 : 0.6)
        .padding(.trailing, 16)
        .padding(.bottom, expanded ? 120 : 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.easeInOut(duration: 0.2), value: expanded)
    }
}
#else
// UIKit 無し環境 (素の macOS) では何もしない
@MainActor
final class AutoScrollController: ObservableObject {
    @Published var isRunning = false
}

struct AutoScrollAttacher: View {
    let controller: AutoScrollController
    var body: some View { EmptyView() }
}

struct AutoScrollButton: View {
    @ObservedObject var controller: AutoScrollController
    let expanded: Bool
    var body: some View { EmptyView() }
}
#endif

/// バー非表示中も左上に残る小さな戻るボタン (mod)
struct ReaderBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.headline.bold())
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 12)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .transition(.opacity)
    }
}

import SwiftUI

/// (mod) ガチャの nhentai 版: nhentai お気に入りからランダムに 1 冊 / 10 冊選ぶ。
/// 結果カードをタップすると詳細画面へ (GachaView 側の navigationDestination を使う)。
struct NhentaiRandomPicker: View {
    @ObservedObject private var nhFavCache = NhentaiFavoritesCache.shared
    @State private var favorites: [NhentaiClient.NhGallery] = []
    @State private var picks: [NhentaiClient.NhGallery] = []
    /// 直近で引いた id (連続で同じ本が出にくくする)
    @State private var recentIds: [Int] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if favorites.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "dice.fill").font(.system(size: 60)).foregroundStyle(.secondary)
                        Text("Add some nhentai favorites first\n(tap ♥ on a book)")
                            .font(.headline).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                    .padding(.top, 80)
                } else {
                    pickButtons

                    ForEach(picks) { nh in
                        NavigationLink(value: nh) {
                            CardDesign.cardChrome(NhentaiCardView(gallery: nh))
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding()
        }
        .onAppear { favorites = nhFavCache.load() }
        .onChange(of: nhFavCache.version) { _, _ in favorites = nhFavCache.load() }
    }

    private var pickButtons: some View {
        VStack(spacing: 12) {
            Button { pick(count: 1) } label: {
                Label("Random book", systemImage: "dice.fill")
                    .font(.title3).bold().frame(maxWidth: 280).padding()
                    .background(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Button { pick(count: 10) } label: {
                Label("Pick 10", systemImage: "sparkles")
                    .font(.title3).bold().frame(maxWidth: 280).padding()
                    .background(LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Text("Picking from \(favorites.count) nhentai favorites")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func pick(count: Int) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        // 直近に出た本は (候補が足りる限り) 避ける
        var pool = favorites.filter { !recentIds.contains($0.id) }
        if pool.count < count { pool = favorites }
        let result = Array(pool.shuffled().prefix(count))
        recentIds = Array((result.map(\.id) + recentIds).prefix(max(0, favorites.count / 2)))
        withAnimation(.spring(duration: 0.35)) { picks = result }
    }
}

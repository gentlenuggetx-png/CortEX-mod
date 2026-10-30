import SwiftUI

/// (mod) ガチャの nhentai 版: nhentai 全体 (任意でタグ/英語のみ) か、お気に入りからランダムに選ぶ。
/// 結果カードをタップすると詳細画面へ (GachaView 側の navigationDestination を使う)。
struct NhentaiRandomPicker: View {
    @ObservedObject private var nhFavCache = NhentaiFavoritesCache.shared
    @AppStorage("nhRandom.fromFavorites") private var fromFavorites = false
    @AppStorage("nhRandom.englishOnly") private var englishOnly = true
    @AppStorage("nhRandom.tags") private var tagText = ""
    @State private var favorites: [NhentaiClient.NhGallery] = []
    @State private var picks: [NhentaiClient.NhGallery] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// 直近で引いた id (お気に入りモードで連続して同じ本が出にくくする)
    @State private var recentIds: [Int] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("From", selection: $fromFavorites) {
                    Text("All nhentai").tag(false)
                    Text("My favorites").tag(true)
                }
                .pickerStyle(.segmented)

                if !fromFavorites {
                    filters
                }

                if fromFavorites && favorites.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "heart").font(.system(size: 50)).foregroundStyle(.secondary)
                        Text("No nhentai favorites yet\n(tap ♥ on a book)")
                            .font(.headline).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)
                } else {
                    pickButtons
                }

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.orange)
                }

                ForEach(picks) { nh in
                    NavigationLink(value: nh) {
                        CardDesign.cardChrome(NhentaiCardView(gallery: nh))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding()
        }
        .onAppear { favorites = nhFavCache.load() }
        .onChange(of: nhFavCache.version) { _, _ in favorites = nhFavCache.load() }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Only with tags (optional, comma separated)", text: $tagText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Toggle("English only", isOn: $englishOnly)
                .font(.subheadline)
        }
    }

    private var pickButtons: some View {
        VStack(spacing: 12) {
            Button { Task { await pick(count: 1) } } label: {
                Label("Random book", systemImage: "dice.fill")
                    .font(.title3).bold().frame(maxWidth: 280).padding()
                    .background(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Button { Task { await pick(count: 10) } } label: {
                Label("Pick 10", systemImage: "sparkles")
                    .font(.title3).bold().frame(maxWidth: 280).padding()
                    .background(LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))
            }
            if isLoading {
                ProgressView("Rolling…")
            } else {
                Text(fromFavorites ? "Picking from \(favorites.count) favorites" : "Picking from all of nhentai")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(isLoading)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 抽選

    private func pick(count: Int) async {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        errorMessage = nil
        if fromFavorites {
            pickFromFavorites(count: count)
            return
        }
        isLoading = true
        defer { isLoading = false }
        withAnimation { picks = [] }
        do {
            let query = searchQuery()
            if query.isEmpty {
                try await pickByRandomId(count: count)
            } else {
                try await pickFromSearch(query: query, count: count)
            }
            if picks.isEmpty { errorMessage = "Nothing found — try fewer tags." }
        } catch {
            errorMessage = "Couldn't reach nhentai: \(error.localizedDescription)"
        }
    }

    private func pickFromFavorites(count: Int) {
        var pool = favorites.filter { !recentIds.contains($0.id) }
        if pool.count < count { pool = favorites }
        let result = Array(pool.shuffled().prefix(count))
        recentIds = Array((result.map(\.id) + recentIds).prefix(max(0, favorites.count / 2)))
        withAnimation(.spring(duration: 0.35)) { picks = result }
    }

    /// 条件なし: 最新 id までの乱数 id で直接取得 (削除済み id は引き直し)
    private func pickByRandomId(count: Int) async throws {
        guard let maxId = try await NhentaiClient.search(query: "", page: 1).result.map(\.id).max() else { return }
        var attempts = 0
        while picks.count < count && attempts < count * 4 {
            attempts += 1
            let id = Int.random(in: 1...maxId)
            guard !picks.contains(where: { $0.id == id }),
                  let g = try? await NhentaiClient.fetchGallery(id: id) else { continue }
            withAnimation(.spring(duration: 0.35)) { picks.append(g) }
        }
    }

    /// 条件あり: 検索結果の総ページ数を調べ、ランダムなページからランダムに 1 冊ずつ
    private func pickFromSearch(query: String, count: Int) async throws {
        let first = try await NhentaiClient.search(query: query, page: 1)
        let pages = max(first.num_pages, 1)
        var cache: [Int: [NhentaiClient.NhGallery]] = [1: first.result]
        var attempts = 0
        while picks.count < count && attempts < count * 4 {
            attempts += 1
            let page = Int.random(in: 1...pages)
            if cache[page] == nil {
                cache[page] = (try? await NhentaiClient.search(query: query, page: page))?.result ?? []
            }
            guard let g = cache[page]?.filter({ c in !picks.contains { $0.id == c.id } }).randomElement() else { continue }
            withAnimation(.spring(duration: 0.35)) { picks.append(g) }
        }
    }

    private func searchQuery() -> String {
        var terms = tagText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
            .map { tag -> String in
                if let colon = tag.firstIndex(of: ":") {
                    let ns = tag[..<colon]
                    let name = tag[tag.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    return "\(ns):\"\(name)\""
                }
                return "tag:\"\(tag)\""
            }
        if englishOnly { terms.append("language:english") }
        return terms.joined(separator: " ")
    }
}

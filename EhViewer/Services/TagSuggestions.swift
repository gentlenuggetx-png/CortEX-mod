import Foundation

/// (mod) 検索画面のタグ候補。よく使われるタグの定数リスト +
/// nhentai お気に入りに付いているタグ (件数順) から、入力中の文字に一致するものを返す。
enum TagSuggestions {

    /// 入力に一致する候補 (最大 limit 件)。前方一致 → 部分一致の順。
    static func matches(for input: String, excluding used: Set<String>, limit: Int = 12) -> [String] {
        let query = input
            .split(separator: ",").last.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
            .lowercased() ?? ""
        let pool = allTags().filter { !used.contains($0) }
        guard !query.isEmpty else { return Array(pool.prefix(limit)) }

        var prefix: [String] = []
        var contains: [String] = []
        for tag in pool {
            // "artist:foo" は名前部分でも一致させる
            let name = tag.split(separator: ":").last.map(String.init) ?? tag
            if tag.hasPrefix(query) || name.hasPrefix(query) {
                prefix.append(tag)
            } else if tag.contains(query) {
                contains.append(tag)
            }
            if prefix.count >= limit { break }
        }
        return Array((prefix + contains).prefix(limit))
    }

    /// お気に入り由来のタグ (使用回数順) → 定番タグ。重複なし。
    static func allTags() -> [String] {
        var counts: [String: Int] = [:]
        for gallery in NhentaiFavoritesCache.shared.load() {
            for tag in gallery.tags ?? [] {
                guard let key = suggestionKey(type: tag.type, name: tag.name) else { continue }
                counts[key, default: 0] += 1
            }
        }
        let fromFavorites = counts.sorted { $0.value > $1.value }.map(\.key)
        var seen = Set<String>()
        return (fromFavorites + popular).filter { seen.insert($0).inserted }
    }

    /// nhentai のタグ種別を検索用の表記に変換 (言語・カテゴリは除外)
    private static func suggestionKey(type: String, name: String) -> String? {
        let name = name.lowercased()
        switch type {
        case "tag": return name
        case "artist", "group", "parody", "character": return "\(type):\(name)"
        default: return nil
        }
    }

    /// 定番タグ (お気に入りが少なくても候補が出るように)
    static let popular: [String] = [
        "big breasts", "sole female", "sole male", "nakadashi", "stockings", "schoolgirl uniform",
        "glasses", "ahegao", "blowjob", "paizuri", "milf", "anal", "lolicon", "shotacon",
        "full color", "uncensored", "mosaic censorship", "netorare", "defloration", "x-ray",
        "group", "harem", "yuri", "yaoi", "futanari", "femdom", "tentacles", "monster girl",
        "dark skin", "elf", "kemonomimi", "cat girl", "fox girl", "bunny girl", "maid", "nurse",
        "swimsuit", "bikini", "pantyhose", "kimono", "school swimsuit", "gym uniform", "bloomers",
        "twintails", "ponytail", "small breasts", "huge breasts", "muscle", "tomboy", "gyaru",
        "teacher", "sister", "mother", "incest", "cheating", "vanilla", "romance", "story arc",
        "mind control", "mind break", "rape", "bondage", "humiliation", "exhibitionism",
        "masturbation", "fingering", "footjob", "handjob", "kissing", "breast feeding",
        "lactation", "pregnant", "impregnation", "virginity", "multi-work series", "tankoubon",
        "anthology", "sweating", "tanlines", "hairy", "collar", "blindfold", "crossdressing",
        "tall girl", "tomgirl", "ghost", "demon girl", "angel", "robot", "witch", "succubus",
        "time stop", "body swap", "gender bender", "transformation", "sleeping", "drunk",
        "parody:original", "parody:touhou project", "parody:kantai collection", "parody:fate grand order",
        "parody:blue archive", "parody:genshin impact", "parody:the idolmaster", "parody:azur lane",
        "parody:pokemon", "parody:hololive", "parody:naruto", "parody:one piece",
        "parody:my hero academia", "parody:love live", "parody:uma musume pretty derby",
    ]
}

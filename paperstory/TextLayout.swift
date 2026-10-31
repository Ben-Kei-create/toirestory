import Foundation

enum Story {
    /// 『走れメロス』冒頭(青空文庫)。試作では冒頭だけを紙に印刷する。
    static let title = "走れメロス"
    static let opening = "メロスは激怒した。必ず、かの邪智暴虐の王を除かなければならぬと決意した。メロスには政治がわからぬ。メロスは、村の牧人である。笛を吹き、羊と遊んで暮して来た。けれども邪悪に対しては、人一倍に敏感であった。"
}

enum TextLayout {
    static let charsPerSegment = 20
    static let maxSegmentChars = 22
    private static let noLineStart: Set<Character> = ["。", "、", "」", "』", "）", "！", "？", "…", "ー"]
    private static let noLineEnd: Set<Character> = ["「", "『", "（"]

    /// 約20文字ごとの区間に組み直す。区間頭に句読点が来ないよう、押し込み/追い出しで調整する。
    static func segments(from text: String, size: Int = charsPerSegment) -> [[Character]] {
        let chars = Array(text.filter { !$0.isNewline && $0 != " " })
        var result: [[Character]] = []
        var start = 0
        while start < chars.count {
            var end = min(start + size, chars.count)
            while end < chars.count, noLineStart.contains(chars[end]), end - start < maxSegmentChars {
                end += 1
            }
            while end < chars.count, end - start > size - 3, noLineEnd.contains(chars[end - 1]) {
                end -= 1
            }
            result.append(Array(chars[start..<end]))
            start = end
        }
        return result
    }
}

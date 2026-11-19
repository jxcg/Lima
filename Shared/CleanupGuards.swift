import Foundation
import NaturalLanguage

// Experimental text guards recovered from the Mac harness, with no retries or fuzzy spelling.
// These are heuristics, not a guarantee that a rewrite preserves meaning.
enum CleanupGuards {
    private static let days: Set<String> = ["monday","tuesday","wednesday","thursday","friday","saturday","sunday","today","tomorrow","tonight"]
    private static let months: Set<String> = ["january","february","march","april","may","june","july","august","september","october","november","december"]
    private static let numbers: Set<String> = ["one","two","three","four","five","six","seven","eight","nine","ten","eleven","twelve","half","noon","midnight"]
    private static let functionWords: Set<String> = ["can","could","we","i","you","it","a","an","the","is","so","and","that","this","to","in","on","at","for"]

    private static func kind(_ word: String) -> String? {
        let token = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if days.contains(token) { return "day" }
        if months.contains(token) { return "month" }
        if numbers.contains(token) || token.first?.isNumber == true { return "number" }
        return nil
    }

    static func prepare(_ raw: String) -> String {
        var words = resolve(raw).split(separator: " ").map(String.init)
        var i = 1
        while i < words.count - 1 {
            let sameKind = kind(words[i - 1]) != nil && kind(words[i - 1]) == kind(words[i + 1])
            let repeated = i >= 2 && words[i + 1].lowercased() == words[i - 2].lowercased()
            if ["no", "sorry"].contains(words[i].lowercased()), sameKind || repeated {
                words[i] = "I mean"
            } else if words[i].lowercased() == "not", sameKind {
                words[i - 1] += ","
                if i + 2 < words.count { words[i + 1] += "," }
            }
            i += 1
        }
        return words.joined(separator: " ")
    }

    private static func markerBlock(_ words: [String], _ start: Int) -> Int? {
        var i = start
        var real = false
        while i < words.count {
            let token = words[i].lowercased()
            if token == "i", i + 1 < words.count, words[i + 1].lowercased() == "mean" {
                real = true; i += 2; continue
            }
            if token == "make", i + 1 < words.count, words[i + 1].lowercased() == "it" {
                real = true; i += 2; continue
            }
            if ["no","wait","sorry","actually"].contains(token) { real = true; i += 1; continue }
            if ["maybe","or","rather"].contains(token) { i += 1; continue }
            break
        }
        return real && i > start && i < words.count ? i : nil
    }

    private static func valueSpan(_ words: [String], at index: Int) -> Range<Int> {
        var lo = index, hi = index + 1
        if lo > 0, ["half","quarter"].contains(words[lo - 1].lowercased()) { lo -= 1 }
        if hi < words.count, words[hi].lowercased() == "o'clock" { hi += 1 }
        return lo..<hi
    }

    private static func resolve(_ raw: String) -> String {
        var words = raw.split(separator: " ").map { $0.replacingOccurrences(of: ",", with: "") }
        var marker = 1
        while marker < words.count - 1 {
            guard let repair = markerBlock(words, marker) else { marker += 1; continue }
            var value = repair
            var preposition: String?
            if ["on","at","by","in","for","until"].contains(words[repair].lowercased()),
               repair + 1 < words.count, kind(words[repair + 1]) != nil {
                preposition = words[repair].lowercased(); value = repair + 1
            }
            if ["half","quarter"].contains(words[value].lowercased()),
               value + 1 < words.count, kind(words[value + 1]) != nil { value += 1 }
            if let repairKind = kind(words[value]), !["half","quarter"].contains(words[value].lowercased()) {
                var oldIndex = marker - 1
                while oldIndex >= max(0, marker - 6),
                      kind(words[oldIndex]) != repairKind || ["half","quarter"].contains(words[oldIndex].lowercased()) { oldIndex -= 1 }
                if oldIndex >= max(0, marker - 6) {
                    var old = valueSpan(words, at: oldIndex)
                    if let preposition, old.lowerBound > 0, words[old.lowerBound - 1].lowercased() == preposition {
                        old = (old.lowerBound - 1)..<old.upperBound
                    }
                    var replacement = valueSpan(words, at: value).clamped(to: repair..<words.count)
                    if preposition != nil { replacement = repair..<replacement.upperBound }
                    if old.upperBound == marker {
                        words.removeSubrange(old.lowerBound..<repair)
                    } else {
                        var replacementWords = Array(words[replacement])
                        let digits = ["one":"1","two":"2","three":"3","four":"4","five":"5","six":"6","seven":"7","eight":"8","nine":"9","ten":"10","eleven":"11","twelve":"12"]
                        if words[oldIndex].first?.isNumber == true {
                            replacementWords = replacementWords.map { digits[$0.lowercased()] ?? $0 }
                        }
                        words.removeSubrange(marker..<replacement.upperBound)
                        words.replaceSubrange(old, with: replacementWords)
                    }
                    marker = max(1, old.lowerBound); continue
                }
            }
            let head = words[repair].lowercased()
            var oldIndex = marker - 1
            while oldIndex >= max(0, marker - 4), words[oldIndex].lowercased() != head { oldIndex -= 1 }
            if oldIndex >= max(0, marker - 4) {
                let twoMatch = repair + 1 < words.count && oldIndex + 1 < marker
                    && words[oldIndex + 1].lowercased() == words[repair + 1].lowercased()
                if !functionWords.contains(head) || twoMatch {
                    words.removeSubrange(oldIndex..<repair); marker = max(1, oldIndex); continue
                }
            }
            let pronouns: Set<String> = ["i","i'm","i'll","i've","i'd"]
            func capitalised(_ index: Int) -> Bool {
                words[index].first?.isUppercase == true && !pronouns.contains(words[index].lowercased())
            }
            if marker - 1 > 0, capitalised(marker - 1), capitalised(repair), words[marker - 1].last?.isLetter == true {
                var start = marker - 1
                while start - 1 > 0, capitalised(start - 1), words[start - 1].last?.isLetter == true { start -= 1 }
                words.removeSubrange(start..<repair); marker = max(1, start); continue
            }
            let markerWords = words[marker..<repair].map { $0.lowercased() }
            if (markerWords == ["i","mean"] || markerWords == ["sorry"]), repair - marker <= 2 {
                let tagger = NLTagger(tagSchemes: [.lexicalClass])
                let text = words.joined(separator: " ")
                tagger.string = text
                func tag(_ index: Int) -> NLTag? {
                    let offset = words[..<index].reduce(0) { $0 + $1.count + 1 }
                    return tagger.tag(at: text.index(text.startIndex, offsetBy: offset), unit: .word, scheme: .lexicalClass).0
                }
                if tag(marker - 1) == .noun, tag(repair) == .noun, !functionWords.contains(words[marker - 1].lowercased()) {
                    words.removeSubrange((marker - 1)..<repair); marker = max(1, marker - 1); continue
                }
            }
            marker = repair
        }
        return words.joined(separator: " ")
    }

    static func finish(raw: String, output: String) -> String {
        var text = String(output.prefix { $0 != "}" }).replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " }]{[\"\\"))
        let keep: Set<String> = ["hey","hi","hello","actually","sorry","thanks","please","honestly"]
        if let first = raw.split(separator: " ").first.map({ $0.lowercased() }), keep.contains(first),
           !text.lowercased().hasPrefix(first) {
            text = first.prefix(1).uppercased() + first.dropFirst() + ", " + text.prefix(1).lowercased() + text.dropFirst()
        }
        if let last = text.last, !".?!".contains(last) { text += "." }
        text = postGuards(raw: raw, output: text)
        if let first = text.first, first.isLowercase { text = first.uppercased() + text.dropFirst() }
        return text
    }

    private static func postGuards(raw: String, output: String) -> String {
        var text = output.trimmingCharacters(in: CharacterSet(charactersIn: "}]\"' "))
        let fillers: Set<String> = ["um","uh","er","erm"]
        let prepared = resolve(raw).split(separator: " ").filter { !fillers.contains($0.lowercased()) }.joined(separator: " ")
        let refusalBits = ["i cannot","i can't help","i can't assist","i'm afraid i","i am unable","i'm unable","cannot fulfil","cannot fulfill","cannot comply","cannot assist","as an ai","provide a message"]
        let refusal = refusalBits.contains { text.lowercased().contains($0) && !prepared.lowercased().contains($0) }
        let inputWords = Set((prepared + " " + raw).lowercased().split(separator: " ").map { $0.trimmingCharacters(in: .punctuationCharacters) })
        let outputWords = text.lowercased().split(separator: " ").map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && $0.first?.isNumber != true }
        if refusal || Double(text.split(separator: " ").count) < 0.4 * Double(prepared.split(separator: " ").count)
            || (outputWords.count >= 4 && Double(outputWords.filter { !inputWords.contains($0) }.count) > 0.5 * Double(outputWords.count)) {
            text = prepared
            if let first = text.first { text = first.uppercased() + text.dropFirst() }
            if let last = text.last, !".?!".contains(last) { text += "." }
        }
        text = text.replacingOccurrences(of: " o'clock", with: "").replacingOccurrences(of: " o’clock", with: "")
        let contractions = [("don't","do not"),("I'll","I will"),("can't","cannot"),("won't","will not"),("it's","it is"),("I'm","I am"),("didn't","did not"),("isn't","is not"),("we'll","we will"),("you're","you are"),("that's","that is")]
        for (short, expanded) in contractions where raw.lowercased().contains(short.lowercased()) {
            text = text.replacingOccurrences(of: expanded, with: short)
                .replacingOccurrences(of: expanded.prefix(1).uppercased() + expanded.dropFirst(), with: short.prefix(1).uppercased() + short.dropFirst())
        }
        func normalise(_ word: String) -> String { word.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        let skip: Set<String> = ["um","uh","er","erm","like","you","know","o'clock","no","wait","mean","make","it","so"]
        let source = prepared.split(separator: " ").map(String.init)
        var result = text.split(separator: " ").map(String.init)
        var i = 1
        while i < source.count {
            let normal = result.map(normalise)
            if normal.contains(normalise(source[i])) || skip.contains(normalise(source[i])) { i += 1; continue }
            var end = i
            while end + 1 < source.count, end - i < 1, !normal.contains(normalise(source[end + 1])), !skip.contains(normalise(source[end + 1])) { end += 1 }
            let previous = normalise(source[i - 1])
            let atEnd = end + 1 >= source.count
            let next = atEnd ? "" : normalise(source[end + 1])
            let markers: Set<String> = ["sorry","actually","no","wait","mean","make"]
            if end > i, source[i...end].contains(where: { markers.contains(normalise($0)) }) { i = end + 1; continue }
            let gap = source[i...end].map { $0.lowercased() == "i" ? "I" : $0.lowercased() }
            var done = false
            for k in 0..<result.count where normal[k] == previous && !done {
                if atEnd, k == result.count - 1 {
                    let core = result[k].trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
                    let punctuation = String(result[k].dropFirst(core.count))
                    result[k] = core + ","
                    result.append(gap.joined(separator: " ") + (punctuation.isEmpty ? "." : punctuation)); done = true
                } else if !atEnd, k + 1 < result.count, normal[k + 1] == next {
                    result.insert(contentsOf: gap, at: k + 1); done = true
                }
            }
            i = end + 1
        }
        text = result.joined(separator: " ")
        let openers: Set<String> = ["sorry","actually","honestly","hey","hi","hello","okay","ok"]
        let following: Set<String> = ["that's","this","we've","they","she","he","let's","what","how","i","i'm","i'll","i've","i'd","we","we're","we'll","you","it","it's","can","could","would","do","are","is","that","the","so","just","my","there"]
        var words = text.split(separator: " ").map(String.init)
        if words.count > 1, openers.contains(words[0].lowercased()), following.contains(words[1].lowercased()) {
            words[0] += ","; text = words.joined(separator: " ")
        }
        for greeting in ["Morning","Hi","Hey","Hello","Evening","Afternoon"]
            where text.hasPrefix(greeting + ", all ") || text.hasPrefix(greeting + ", everyone ") {
            let rest = text.dropFirst(greeting.count + 2)
            if let space = rest.firstIndex(of: " ") { text = greeting + " " + rest[..<space] + "," + rest[space...] }
        }
        if text.hasSuffix(".") {
            let lastSentence = text.dropLast().components(separatedBy: ". ").last ?? ""
            var words = lastSentence.lowercased().split(separator: " ").map { $0.trimmingCharacters(in: .punctuationCharacters) }
            let leads: Set<String> = ["hey","hi","hello","actually","sorry","so","okay","ok","right","please","oh"]
            while let first = words.first, leads.contains(first) { words.removeFirst() }
            let questions: Set<String> = ["can","could","would","will","are","is","do","does","did","shall","should","what","when","where","who","why","how","have","has"]
            if let first = words.first, questions.contains(first) { text = String(text.dropLast()) + "?" }
        }
        return text
    }
}

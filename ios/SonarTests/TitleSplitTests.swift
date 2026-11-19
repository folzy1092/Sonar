import XCTest
@testable import Sonar

/// Разбор перезаливов — порт `windows/src-tauri/src/lyrics/title_split_tests.rs` (все случаи docs/TITLE_SPLIT.md).
final class TitleSplitTests: XCTestCase {
    private func p(_ a: String, _ t: String) -> TitlePair { TitlePair(a, t) }

    private func variants(_ artist: String, _ title: String) -> [TitlePair] {
        TitleSplit.reuploadVariants(artist: artist, title: title)
    }

    private func pair(_ artist: String, _ title: String) -> TitlePair {
        TitleSplit.searchPair(artist: artist, title: title)
    }

    /// Начало списка совпадает; исходной пары нет; вариантов ≤ 4.
    private func starts(_ artist: String, _ title: String, _ head: [(String, String)], line: UInt = #line) {
        let got = variants(artist, title)
        let want = head.map { p($0.0, $0.1) }
        XCTAssertTrue(got.count >= want.count && Array(got.prefix(want.count)) == want, "\(artist) / \(title): \(got)", line: line)
        XCTAssertFalse(got.contains(p(artist, title)), "\(artist) / \(title): исходная пара в списке", line: line)
        XCTAssertLessThanOrEqual(got.count, TitleSplit.maxVariants, line: line)
    }

    func testTableFromSpec() {
        starts("juchen", "gothviolence – не могу уснуть", [("gothviolence", "не могу уснуть")])
        starts("гниющая плесень", "gothviolence — they wanna kill themselves when I hang up",
               [("gothviolence", "they wanna kill themselves when I hang up")])
        starts("mereana mordegard⛧⸸", "cowboyclicker - RUSSIAN ROULETTE  archive",
               [("cowboyclicker", "RUSSIAN ROULETTE  archive"), ("cowboyclicker", "RUSSIAN ROULETTE")])
        starts("fleurnothappy", "fleurnothappy - hermaeus mora prod @cl6udly",
               [("fleurnothappy", "hermaeus mora prod @cl6udly"), ("fleurnothappy", "hermaeus mora")])
        starts("Bones", "Bones - Sodium", [("Bones", "Sodium")])
        starts("ШИПЫ", "VZk1ll Turbo 2000, ШИПЫ - Mr.Bigbucks Cxsinoslayer 2016",
               [("VZk1ll Turbo 2000, ШИПЫ", "Mr.Bigbucks Cxsinoslayer 2016")])
        starts("ШИПЫ", "cowboyclicker x ШИПЫ - fuck you", [("cowboyclicker x ШИПЫ", "fuck you")])
        starts("playerwithoutheart", "Russianmafiaextra X Cowboyclicker – Awake", [("Russianmafiaextra X Cowboyclicker", "Awake")])
        starts("урал гайсин", "bigpluggssd feat. фолли - сучка сосет достала.мп3",
               [("bigpluggssd feat. фолли", "сучка сосет достала.мп3"), ("bigpluggssd feat. фолли", "сучка сосет достала")])
        starts("KUDOKUSHI, AQUAKEY", "KUDOKUSHI, AQUKAEY - same problems", [("KUDOKUSHI, AQUKAEY", "same problems")])
        starts("анатолий балансиага", "анатолий балансиага, eliass - angelsnumber", [("анатолий балансиага, eliass", "angelsnumber")])
        starts("@leilahimikat", "+ ONDA ANDAR - Нацеди мне", [("ONDA ANDAR", "Нацеди мне")])
        starts("leilahimikat", "+ШИПЫ/ONDA ANDAR - sоrты яdа", [("ШИПЫ", "sоrты яdа")])
        starts("@extra", "@russianmafiaextra + cowboyclicker - awake p/quazar",
               [("russianmafiaextra + cowboyclicker", "awake p/quazar"), ("russianmafiaextra + cowboyclicker", "awake")])
        starts("~ Slump Audios Radio ~", "cowboyclicker - fall (nepuhz) [slump audios exclusive + v8gve]",
               [("cowboyclicker", "fall (nepuhz) [slump audios exclusive + v8gve]"), ("cowboyclicker", "fall")])
        starts("щщщ", "gothviolence - Не Найдёшь Меня +mor+alyen+sydniy",
               [("gothviolence", "Не Найдёшь Меня +mor+alyen+sydniy"), ("gothviolence", "Не Найдёшь Меня")])
        starts("justinhoward", "ШИПЫ - ChainMail_{{Sp1keSpells77}}#2016 [prod hatred.exe]",
               [("ШИПЫ", "ChainMail_{{Sp1keSpells77}}#2016 [prod hatred.exe]"), ("ШИПЫ", "ChainMail_{{Sp1keSpells77}}")])
        starts("культ", "gothviolence - theydonknowme prod kilolit",
               [("gothviolence", "theydonknowme prod kilolit"), ("gothviolence", "theydonknowme")])
        starts("17.javelin", "cowboyclicker - no tomorrow prod. skorpy",
               [("cowboyclicker", "no tomorrow prod. skorpy"), ("cowboyclicker", "no tomorrow")])
        starts("yaphula", "jaydes - migraine @beabadoobee", [("jaydes", "migraine @beabadoobee"), ("jaydes", "migraine")])
        starts("мельников", "gothviolence – i dontbelieve the words anymore... im takin yr sWAG.mp3", [
            ("gothviolence", "i dontbelieve the words anymore... im takin yr sWAG.mp3"),
            ("gothviolence", "i dontbelieve the words anymore... im takin yr sWAG"),
        ])
        starts("eternalfearofgod", "cowboyclicker - fishing ft. tarozan(slowed+reverb)",
               [("cowboyclicker", "fishing ft. tarozan(slowed+reverb)"), ("cowboyclicker", "fishing")])
        starts("ALIK SHAWARMA", "cowboyclicker - idontwanna(without helios812)",
               [("cowboyclicker", "idontwanna(without helios812)"), ("cowboyclicker", "idontwanna")])
        starts("1nv6l1d", "Овсянкин - Red lipstick + 2 lines", [("Овсянкин", "Red lipstick + 2 lines"), ("Овсянкин", "Red lipstick")])
        starts("six", "yuke - gone (edited)", [("yuke", "gone (edited)"), ("yuke", "gone")])
        starts("SEMATARY", "SEMATARY FT. GHOST MOUNTAIN - BUNNY SUIT **VIDEO IN DESCRIPTION**", [
            ("SEMATARY FT. GHOST MOUNTAIN", "BUNNY SUIT **VIDEO IN DESCRIPTION**"),
            ("SEMATARY FT. GHOST MOUNTAIN", "BUNNY SUIT"),
        ])
        starts("#некийй парень", "BENJAMINGOTBENZ - MOONLIGHT ANGEL SPEED X MIX",
               [("BENJAMINGOTBENZ", "MOONLIGHT ANGEL SPEED X MIX"), ("BENJAMINGOTBENZ", "MOONLIGHT ANGEL")])
        starts("imurcurse", "ONDA ANDAR – SHIPY DOWNHEAD RACING #2016",
               [("ONDA ANDAR", "SHIPY DOWNHEAD RACING #2016"), ("ONDA ANDAR", "SHIPY DOWNHEAD RACING")])
        starts("mirror private club", "ШИПЫ - Krovat' 1й парт", [("ШИПЫ", "Krovat' 1й парт"), ("ШИПЫ", "Krovat'")])
        starts("43", "REMIX - BIG BABY TAPE & KIZARU - BON VOYAGE (prod by. @threen1ne)",
               [("BIG BABY TAPE & KIZARU", "BON VOYAGE (prod by. @threen1ne)"), ("BIG BABY TAPE & KIZARU", "BON VOYAGE")])
        starts("мадвей", "сны не меняются(full) - onda andar", [("сны не меняются", "onda andar"), ("onda andar", "сны не меняются")])
        starts("Alex G", "east coast - alex g", [("Alex G", "east coast"), ("east coast", "alex g")])
        XCTAssertEqual(variants("BATO", "BATO - Miura 2"), [p("BATO", "Miura 2")])
    }

    func testSwapNeedsProof() {
        XCTAssertEqual(variants("мадвей", "сны не меняются(full) - onda andar").last, p("onda andar", "сны не меняются"))
        XCTAssertEqual(variants("x", "клип.mp3 - Some Artist").last, p("Some Artist", "клип"))
        XCTAssertEqual(variants("Alex G", "east coast - alex g").first, p("Alex G", "east coast"))
        XCTAssertEqual(variants("russianmafiaextra", "russianmafiaextra - hello past"), [p("russianmafiaextra", "hello past")])
        XCTAssertEqual(variants("juchen", "gothviolence – не могу уснуть").count, 1)
        XCTAssertEqual(variants("blissful", "Дарк Бриллиант Корсес - Anniversary"), [p("Дарк Бриллиант Корсес", "Anniversary")])
        let got = variants("Alex G", "Alex G | east coast - alex g (full)")
        let folded = Set(got.map { [TitleSplit.fold($0.artist), TitleSplit.fold($0.title)] })
        XCTAssertEqual(folded.count, got.count, "повторы: \(got)")
        XCTAssertEqual(got.filter { TitleSplit.fold($0.title).hasPrefix("alex g |") }.count, 1, "\(got)")
    }

    func testNoSeparatorNoVariants() {
        for title in ["Mr.Bigbucks", "ONDA ANDAR", "", "   ", "a - ", " - b", "T-Shirt", "Self-Obsession"] {
            XCTAssertTrue(variants("x", title).isEmpty, title)
        }
        XCTAssertEqual(variants("x", "Self-Obsession - Track").first, p("Self-Obsession", "Track"))
    }

    func testOriginalPairNeverReturned() {
        XCTAssertFalse(variants("A", "a - A").contains(p("A", "a - A")))
        XCTAssertEqual(variants("ab", "AB - ab"), [p("ab", "ab")])
        let many = variants("x", "Aa - Bb - Cc - Dd")
        XCTAssertTrue(many.count >= 2 && many.count <= TitleSplit.maxVariants)
        XCTAssertEqual(many, variants("x", "Aa - Bb - Cc - Dd"))
        XCTAssertEqual(variants("x", "Bones - Bones"), [p("Bones", "Bones")])
        let three = variants("x", "Artist - Middle - Track")
        XCTAssertTrue(three.contains(p("Artist", "Middle - Track")) && three.contains(p("Artist - Middle", "Track")))
        XCTAssertEqual(variants("x", "AC/DC - Hells Bells").first, p("AC/DC", "Hells Bells"))
        XCTAssertEqual(TitleSplit.cleanTitle("Product Of Love"), "Product Of Love")
    }

    func testSearchPairCases() {
        XCTAssertEqual(pair("juchen", "gothviolence – не могу уснуть"), p("gothviolence", "не могу уснуть"))
        XCTAssertEqual(pair("x", "cowboyclicker - fall (nepuhz)"), p("cowboyclicker", "fall"))
        XCTAssertEqual(pair("x", "no separator"), p("x", "no separator"))
        XCTAssertEqual(pair("Alex G", "east coast - alex g"), p("Alex G", "east coast"))
    }

    func testLabelOnlyRightPart() {
        for title in [
            "Creep - Live", "Time - 2011 Remaster", "Song - Radio Edit", "Runaway - Radio Edit", "X - Remix",
            "Song - Acoustic Version", "Song - Remastered 2009", "Song - Remaster(ed)", "Song - Sped Up",
            "Song - Extended Mix", "Song - Original Mix", "Song - Instrumental", "Song - Deluxe Edition", "Song - Mono",
            "Song - 1999", "Song - Ремикс", "Song - Слоуд", "Song - Slowed + Reverb", "Song - (Live)",
            "Song - feat. Someone", "Song - prod. Someone",
        ] {
            XCTAssertTrue(variants("Some Band", title).isEmpty, title)
            XCTAssertEqual(pair("Some Band", title), p("Some Band", title))
        }
    }

    func testCleanTitleLabelTails() {
        for title in ["Song - Slowed", "Song - Radio Edit", "Song - slowed", "Song —"] {
            XCTAssertEqual(TitleSplit.cleanTitle(title), "Song", title)
        }
        XCTAssertEqual(variants("u", "Artist - Song - Slowed"), [p("Artist", "Song - Slowed"), p("Artist", "Song")])
        XCTAssertEqual(pair("u", "Artist - Song - Slowed"), p("Artist", "Song"))
        let kanye = variants("u", "Kanye West - Power - Remix")
        XCTAssertTrue(kanye.allSatisfy { $0.title != "Remix" }, "\(kanye)")
        XCTAssertTrue(kanye.contains(p("Kanye West", "Power")))
        XCTAssertEqual(pair("u", "Kanye West - Power - Remix"), p("Kanye West", "Power"))
    }

    func testNoiseInsteadOfTitle() {
        for title in ["Artist - prod", "Artist - feat. X", "Artist - ft. Y", "Artist - #1", "Artist - prod. beats", "Artist - 7", "A - Song"] {
            XCTAssertTrue(variants("Some Band", title).isEmpty, title)
            XCTAssertEqual(pair("Some Band", title), p("Some Band", title))
        }
    }

    func testDashDictionaryDefault() {
        XCTAssertEqual(variants("автор", "cowboyclicker-трек"), [p("cowboyclicker", "трек")])
        XCTAssertEqual(variants("автор", "CowboyClicker–Трек"), [p("CowboyClicker", "Трек")])
        XCTAssertEqual(variants("автор", "cowboyclicker -трек"), [p("cowboyclicker", "трек")])
        XCTAssertEqual(variants("автор", "cowboyclicker- трек"), [p("cowboyclicker", "трек")])
        XCTAssertEqual(variants("автор", "cowboyclicker-трек (prod. x)").last, p("cowboyclicker", "трек"))
        XCTAssertEqual(pair("автор", "cowboyclicker-трек"), p("cowboyclicker", "трек"))
        for title in ["T-Shirt", "Self-Obsession", "Jay-Z", "cowboyclickers-трек", "cowboyclicker", "cowboyclicker-", "my cowboyclicker-трек"] {
            XCTAssertTrue(variants("автор", title).isEmpty, title)
        }
        XCTAssertEqual(variants("автор", "cowboyclicker x шипы - fuck you"), [p("cowboyclicker x шипы", "fuck you")])
    }

    func testDashDictionaryChanges() {
        let dict = DashArtists(["jay-z", "wu tang"])
        XCTAssertEqual(dict.names, ["wu tang", "jay-z"])
        XCTAssertEqual(TitleSplit.reuploadVariants(artist: "x", title: "jay-z-99 problems", dash: dict), [p("jay-z", "99 problems")])
        XCTAssertEqual(TitleSplit.reuploadVariants(artist: "x", title: "Wu Tang-C.R.E.A.M.", dash: dict), [p("Wu Tang", "C.R.E.A.M.")])
        XCTAssertTrue(TitleSplit.reuploadVariants(artist: "x", title: "cowboyclicker-трек", dash: dict).isEmpty)
        let without = DashArtists(["wu tang"])
        XCTAssertTrue(TitleSplit.reuploadVariants(artist: "x", title: "jay-z-99 problems", dash: without).isEmpty)
    }

    func testDashNameNormalization() {
        XCTAssertEqual(TitleSplit.normalizeDashName("  @CowboyClicker \n"), "cowboyclicker")
        XCTAssertEqual(TitleSplit.normalizeDashName("Sad  Boy"), "sad boy")
        for junk in ["a", "--", "", "a\nb"] {
            XCTAssertNil(TitleSplit.normalizeDashName(junk), junk)
        }
        XCTAssertNil(TitleSplit.normalizeDashName(String(repeating: "a", count: 41)))
        XCTAssertEqual(DashArtists.fromLoaded(nil).names, ["cowboyclicker"])
        XCTAssertTrue(DashArtists.fromLoaded([]).names.isEmpty)
    }
}

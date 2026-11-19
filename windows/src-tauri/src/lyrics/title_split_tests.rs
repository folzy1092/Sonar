//! Тесты разбора перезаливов — все случаи из docs/TITLE_SPLIT.md «Тесты».

use super::*;

fn p(a: &str, t: &str) -> Pair {
  (a.to_string(), t.to_string())
}

fn variants(artist: &str, title: &str) -> Vec<Pair> {
  reupload_variants(artist, title, &DashArtists::default())
}

fn pair(artist: &str, title: &str) -> Pair {
  search_pair(artist, title, &DashArtists::default())
}

/// Начало списка совпадает; исходной пары нет; вариантов ≤ 4.
fn starts(artist: &str, title: &str, head: &[(&str, &str)]) {
  let got = variants(artist, title);
  let want: Vec<Pair> = head.iter().map(|(a, t)| p(a, t)).collect();
  assert!(got.len() >= want.len() && got[..want.len()] == want[..], "{artist} / {title}: {got:?}");
  assert!(!got.contains(&p(artist, title)), "{artist} / {title}: исходная пара в списке");
  assert!(got.len() <= MAX_VARIANTS);
}

#[test]
fn table_from_spec() {
  let cases: &[(&str, &str, &[(&str, &str)])] = &[
    ("juchen", "gothviolence – не могу уснуть", &[("gothviolence", "не могу уснуть")]),
    (
      "гниющая плесень",
      "gothviolence — they wanna kill themselves when I hang up",
      &[("gothviolence", "they wanna kill themselves when I hang up")],
    ),
    (
      "mereana mordegard⛧⸸",
      "cowboyclicker - RUSSIAN ROULETTE  archive",
      &[("cowboyclicker", "RUSSIAN ROULETTE  archive"), ("cowboyclicker", "RUSSIAN ROULETTE")],
    ),
    (
      "fleurnothappy",
      "fleurnothappy - hermaeus mora prod @cl6udly",
      &[("fleurnothappy", "hermaeus mora prod @cl6udly"), ("fleurnothappy", "hermaeus mora")],
    ),
    ("Bones", "Bones - Sodium", &[("Bones", "Sodium")]),
    (
      "ШИПЫ",
      "VZk1ll Turbo 2000, ШИПЫ - Mr.Bigbucks Cxsinoslayer 2016",
      &[("VZk1ll Turbo 2000, ШИПЫ", "Mr.Bigbucks Cxsinoslayer 2016")],
    ),
    ("ШИПЫ", "cowboyclicker x ШИПЫ - fuck you", &[("cowboyclicker x ШИПЫ", "fuck you")]),
    ("playerwithoutheart", "Russianmafiaextra X Cowboyclicker – Awake", &[("Russianmafiaextra X Cowboyclicker", "Awake")]),
    (
      "урал гайсин",
      "bigpluggssd feat. фолли - сучка сосет достала.мп3",
      &[("bigpluggssd feat. фолли", "сучка сосет достала.мп3"), ("bigpluggssd feat. фолли", "сучка сосет достала")],
    ),
    ("KUDOKUSHI, AQUAKEY", "KUDOKUSHI, AQUKAEY - same problems", &[("KUDOKUSHI, AQUKAEY", "same problems")]),
    ("анатолий балансиага", "анатолий балансиага, eliass - angelsnumber", &[("анатолий балансиага, eliass", "angelsnumber")]),
    ("@leilahimikat", "+ ONDA ANDAR - Нацеди мне", &[("ONDA ANDAR", "Нацеди мне")]),
    ("leilahimikat", "+ШИПЫ/ONDA ANDAR - sоrты яdа", &[("ШИПЫ", "sоrты яdа")]),
    (
      "@extra",
      "@russianmafiaextra + cowboyclicker - awake p/quazar",
      &[("russianmafiaextra + cowboyclicker", "awake p/quazar"), ("russianmafiaextra + cowboyclicker", "awake")],
    ),
    (
      "~ Slump Audios Radio ~",
      "cowboyclicker - fall (nepuhz) [slump audios exclusive + v8gve]",
      &[("cowboyclicker", "fall (nepuhz) [slump audios exclusive + v8gve]"), ("cowboyclicker", "fall")],
    ),
    (
      "щщщ",
      "gothviolence - Не Найдёшь Меня +mor+alyen+sydniy",
      &[("gothviolence", "Не Найдёшь Меня +mor+alyen+sydniy"), ("gothviolence", "Не Найдёшь Меня")],
    ),
    (
      "justinhoward",
      "ШИПЫ - ChainMail_{{Sp1keSpells77}}#2016 [prod hatred.exe]",
      &[("ШИПЫ", "ChainMail_{{Sp1keSpells77}}#2016 [prod hatred.exe]"), ("ШИПЫ", "ChainMail_{{Sp1keSpells77}}")],
    ),
    (
      "культ",
      "gothviolence - theydonknowme prod kilolit",
      &[("gothviolence", "theydonknowme prod kilolit"), ("gothviolence", "theydonknowme")],
    ),
    (
      "17.javelin",
      "cowboyclicker - no tomorrow prod. skorpy",
      &[("cowboyclicker", "no tomorrow prod. skorpy"), ("cowboyclicker", "no tomorrow")],
    ),
    ("yaphula", "jaydes - migraine @beabadoobee", &[("jaydes", "migraine @beabadoobee"), ("jaydes", "migraine")]),
    (
      "мельников",
      "gothviolence – i dontbelieve the words anymore... im takin yr sWAG.mp3",
      &[
        ("gothviolence", "i dontbelieve the words anymore... im takin yr sWAG.mp3"),
        ("gothviolence", "i dontbelieve the words anymore... im takin yr sWAG"),
      ],
    ),
    (
      "eternalfearofgod",
      "cowboyclicker - fishing ft. tarozan(slowed+reverb)",
      &[("cowboyclicker", "fishing ft. tarozan(slowed+reverb)"), ("cowboyclicker", "fishing")],
    ),
    (
      "ALIK SHAWARMA",
      "cowboyclicker - idontwanna(without helios812)",
      &[("cowboyclicker", "idontwanna(without helios812)"), ("cowboyclicker", "idontwanna")],
    ),
    ("1nv6l1d", "Овсянкин - Red lipstick + 2 lines", &[("Овсянкин", "Red lipstick + 2 lines"), ("Овсянкин", "Red lipstick")]),
    ("six", "yuke - gone (edited)", &[("yuke", "gone (edited)"), ("yuke", "gone")]),
    (
      "SEMATARY",
      "SEMATARY FT. GHOST MOUNTAIN - BUNNY SUIT **VIDEO IN DESCRIPTION**",
      &[
        ("SEMATARY FT. GHOST MOUNTAIN", "BUNNY SUIT **VIDEO IN DESCRIPTION**"),
        ("SEMATARY FT. GHOST MOUNTAIN", "BUNNY SUIT"),
      ],
    ),
    (
      "#некийй парень",
      "BENJAMINGOTBENZ - MOONLIGHT ANGEL SPEED X MIX",
      &[("BENJAMINGOTBENZ", "MOONLIGHT ANGEL SPEED X MIX"), ("BENJAMINGOTBENZ", "MOONLIGHT ANGEL")],
    ),
    (
      "imurcurse",
      "ONDA ANDAR – SHIPY DOWNHEAD RACING #2016",
      &[("ONDA ANDAR", "SHIPY DOWNHEAD RACING #2016"), ("ONDA ANDAR", "SHIPY DOWNHEAD RACING")],
    ),
    ("mirror private club", "ШИПЫ - Krovat' 1й парт", &[("ШИПЫ", "Krovat' 1й парт"), ("ШИПЫ", "Krovat'")]),
    (
      "43",
      "REMIX - BIG BABY TAPE & KIZARU - BON VOYAGE (prod by. @threen1ne)",
      &[("BIG BABY TAPE & KIZARU", "BON VOYAGE (prod by. @threen1ne)"), ("BIG BABY TAPE & KIZARU", "BON VOYAGE")],
    ),
    (
      "мадвей",
      "сны не меняются(full) - onda andar",
      &[("сны не меняются", "onda andar"), ("onda andar", "сны не меняются")],
    ),
    ("Alex G", "east coast - alex g", &[("Alex G", "east coast"), ("east coast", "alex g")]),
  ];
  for (artist, title, head) in cases {
    starts(artist, title, head);
  }
  assert_eq!(variants("BATO", "BATO - Miura 2"), vec![p("BATO", "Miura 2")]);
}

#[test]
fn swap_needs_proof() {
  assert_eq!(variants("мадвей", "сны не меняются(full) - onda andar").last(), Some(&p("onda andar", "сны не меняются")));
  assert_eq!(variants("x", "клип.mp3 - Some Artist").last(), Some(&p("Some Artist", "клип")));
  assert_eq!(variants("Alex G", "east coast - alex g").first(), Some(&p("Alex G", "east coast")));
  assert_eq!(variants("russianmafiaextra", "russianmafiaextra - hello past"), vec![p("russianmafiaextra", "hello past")]);
  assert_eq!(variants("juchen", "gothviolence – не могу уснуть").len(), 1);
  assert_eq!(
    variants("blissful", "Дарк Бриллиант Корсес - Anniversary"),
    vec![p("Дарк Бриллиант Корсес", "Anniversary")]
  );
  let got = variants("Alex G", "Alex G | east coast - alex g (full)");
  let folded: HashSet<(String, String)> = got.iter().map(|(a, t)| (fold(a), fold(t))).collect();
  assert_eq!(folded.len(), got.len(), "повторы: {got:?}");
  assert_eq!(got.iter().filter(|(_, t)| fold(t).starts_with("alex g |")).count(), 1, "{got:?}");
}

#[test]
fn no_separator_no_variants() {
  for title in ["Mr.Bigbucks", "ONDA ANDAR", "", "   ", "a - ", " - b", "T-Shirt", "Self-Obsession"] {
    assert!(variants("x", title).is_empty(), "{title:?}");
  }
  assert_eq!(variants("x", "Self-Obsession - Track").first(), Some(&p("Self-Obsession", "Track")));
}

#[test]
fn original_pair_never_returned() {
  assert!(!variants("A", "a - A").contains(&p("A", "a - A")));
  assert_eq!(variants("ab", "AB - ab"), vec![p("ab", "ab")]);
  let many = variants("x", "Aa - Bb - Cc - Dd");
  assert!(many.len() >= 2 && many.len() <= MAX_VARIANTS);
  assert_eq!(many, variants("x", "Aa - Bb - Cc - Dd"));
  assert_eq!(variants("x", "Bones - Bones"), vec![p("Bones", "Bones")]);
  let three = variants("x", "Artist - Middle - Track");
  assert!(three.contains(&p("Artist", "Middle - Track")) && three.contains(&p("Artist - Middle", "Track")));
  assert_eq!(variants("x", "AC/DC - Hells Bells").first(), Some(&p("AC/DC", "Hells Bells")));
  assert_eq!(clean_title("Product Of Love"), "Product Of Love");
}

#[test]
fn search_pair_cases() {
  assert_eq!(pair("juchen", "gothviolence – не могу уснуть"), p("gothviolence", "не могу уснуть"));
  assert_eq!(pair("x", "cowboyclicker - fall (nepuhz)"), p("cowboyclicker", "fall"));
  assert_eq!(pair("x", "no separator"), p("x", "no separator"));
  assert_eq!(pair("Alex G", "east coast - alex g"), p("Alex G", "east coast"));
}

#[test]
fn label_only_right_part() {
  for title in [
    "Creep - Live", "Time - 2011 Remaster", "Song - Radio Edit", "Runaway - Radio Edit", "X - Remix",
    "Song - Acoustic Version", "Song - Remastered 2009", "Song - Remaster(ed)", "Song - Sped Up",
    "Song - Extended Mix", "Song - Original Mix", "Song - Instrumental", "Song - Deluxe Edition", "Song - Mono",
    "Song - 1999", "Song - Ремикс", "Song - Слоуд", "Song - Slowed + Reverb", "Song - (Live)",
    "Song - feat. Someone", "Song - prod. Someone",
  ] {
    assert!(variants("Some Band", title).is_empty(), "{title}");
    assert_eq!(pair("Some Band", title), p("Some Band", title));
  }
}

#[test]
fn clean_title_label_tails() {
  for title in ["Song - Slowed", "Song - Radio Edit", "Song - slowed", "Song —"] {
    assert_eq!(clean_title(title), "Song", "{title}");
  }
  assert_eq!(variants("u", "Artist - Song - Slowed"), vec![p("Artist", "Song - Slowed"), p("Artist", "Song")]);
  assert_eq!(pair("u", "Artist - Song - Slowed"), p("Artist", "Song"));
  let kanye = variants("u", "Kanye West - Power - Remix");
  assert!(kanye.iter().all(|(_, t)| t != "Remix"), "{kanye:?}");
  assert!(kanye.contains(&p("Kanye West", "Power")));
  assert_eq!(pair("u", "Kanye West - Power - Remix"), p("Kanye West", "Power"));
}

#[test]
fn noise_instead_of_title() {
  for title in ["Artist - prod", "Artist - feat. X", "Artist - ft. Y", "Artist - #1", "Artist - prod. beats", "Artist - 7", "A - Song"] {
    assert!(variants("Some Band", title).is_empty(), "{title}");
    assert_eq!(pair("Some Band", title), p("Some Band", title));
  }
}

#[test]
fn dash_dictionary_default() {
  assert_eq!(variants("автор", "cowboyclicker-трек"), vec![p("cowboyclicker", "трек")]);
  assert_eq!(variants("автор", "CowboyClicker–Трек"), vec![p("CowboyClicker", "Трек")]);
  assert_eq!(variants("автор", "cowboyclicker -трек"), vec![p("cowboyclicker", "трек")]);
  assert_eq!(variants("автор", "cowboyclicker- трек"), vec![p("cowboyclicker", "трек")]);
  assert_eq!(variants("автор", "cowboyclicker-трек (prod. x)").last(), Some(&p("cowboyclicker", "трек")));
  assert_eq!(pair("автор", "cowboyclicker-трек"), p("cowboyclicker", "трек"));
  for title in ["T-Shirt", "Self-Obsession", "Jay-Z", "cowboyclickers-трек", "cowboyclicker", "cowboyclicker-", "my cowboyclicker-трек"] {
    assert!(variants("автор", title).is_empty(), "{title}");
  }
  assert_eq!(variants("автор", "cowboyclicker x шипы - fuck you"), vec![p("cowboyclicker x шипы", "fuck you")]);
}

#[test]
fn dash_dictionary_changes() {
  let dict = DashArtists::new(["jay-z", "wu tang"]);
  assert_eq!(dict.names(), ["wu tang", "jay-z"]);
  assert_eq!(reupload_variants("x", "jay-z-99 problems", &dict), vec![p("jay-z", "99 problems")]);
  assert_eq!(reupload_variants("x", "Wu Tang-C.R.E.A.M.", &dict), vec![p("Wu Tang", "C.R.E.A.M.")]);
  assert!(reupload_variants("x", "cowboyclicker-трек", &dict).is_empty());
  let without = DashArtists::new(["wu tang"]);
  assert!(reupload_variants("x", "jay-z-99 problems", &without).is_empty());
}

#[test]
fn dash_name_normalization() {
  assert_eq!(normalize_dash_name("  @CowboyClicker \n").as_deref(), Some("cowboyclicker"));
  assert_eq!(normalize_dash_name("Sad  Boy").as_deref(), Some("sad boy"));
  for junk in ["a", "--", "", "a\nb"] {
    assert_eq!(normalize_dash_name(junk), None, "{junk:?}");
  }
  assert_eq!(normalize_dash_name(&"a".repeat(41)), None);
  assert_eq!(DashArtists::from_loaded::<String>(None).names(), ["cowboyclicker"]);
  assert!(DashArtists::from_loaded(Some(Vec::<String>::new())).names().is_empty());
}

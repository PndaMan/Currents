# App Store listing

Everything that goes into App Store Connect for Currents lives here, so it is versioned with the code and can be reviewed like code.

```
docs/app-store/
├── README.md                       this file: audit, keyword research, what to paste where
├── metadata/
│   ├── en-US/                      primary localisation (US storefront and every storefront without its own)
│   ├── en-GB/                      UK, South Africa, Ireland and other "English (U.K.)" storefronts
│   └── es-MX/keywords.txt          extra keywords the US storefront also indexes (see "Locales")
└── screenshots/captions.json       headline + sub-line drawn above each screenshot
```

The file names match the layout `fastlane deliver` expects, so the folder can be uploaded with fastlane later without renaming anything. Until then, paste by hand.

Check limits before pasting:

```
make app-store-check
```

## What the live listing looks like today

Checked 22 Oct 2026 on the US and South African storefronts (id6771932525, version 1.2.0).

| Field | Live value | Problem |
|---|---|---|
| Name | Currents Fishing App | 20 of 30 characters used. "Forecast", the strongest term the app can own, is missing. |
| Subtitle | Forecast, Log & Find Fish | "Log" and "Find" on their own match nothing anyone searches. |
| Keywords | not visible outside App Store Connect | Unknown. Treat as unset. |
| Promotional text | empty | 170 free characters, editable without a release. |
| Description | 7 sections from 1.0 | No mention of Community, crews, tournaments, Apple Watch, Siri, fish ID, licences, boat ramps, achievements or AR measuring. Ends on a one-line sign-off. |
| What's New | 1.2.0 notes | Fine, but nothing since (comments, challenges, custom scoring, mythic badges). |
| Screenshots | 5 phone + 1 watch, no captions | Apple allows 10 per device. Every competitor in the top 10 for "fishing app" captions theirs. |
| Category | Sports, secondary Weather | Good. Fishing Points and Fishbrain are both in Sports. |
| Ratings | 3 (ZA), 1 (US), all 5 stars | Too few to rank on. The app already has a review prompt; see "Ratings" below. |

## How App Store search ranks

Apple indexes three fields for search: the name, the subtitle and the 100-byte keyword field, in that order of weight. The description, promotional text and What's New are not indexed; they exist to convert a visitor who has already found the page. Words from the three indexed fields combine with each other, so "fishing" in the name plus "times" in the keywords matches a search for "fishing times". A word in the name should never be repeated in the keywords, because the repeat earns nothing and the bytes could hold another term.

Apple matches singular and plural forms loosely, so "tide" and "tides" cover each other. It does not stem "fishing" to "fish", so both are needed if both searches matter, and for this app they do ("fishing app", "fish identifier").

Sources for the rules: [Apple's product page guide](https://developer.apple.com/app-store/product-page/), [AppTweak on keyword research](https://www.apptweak.com/en/aso-blog/best-aso-keyword-research-tools), [MobileAction's 2026 notes on specific terms beating broad ones](https://www.mobileaction.co/?p=16556).

## Keyword research

Apple publishes no search volumes. The research below comes from two things that are free and current: which apps the App Store search API returns for each term (and how many ratings they have, a proxy for how contested the term is), and the titles and subtitles those apps chose, since a well-funded competitor's title is a bought-and-paid-for keyword study.

### What the top apps put in their titles

| App | Ratings (US) | Name | Subtitle |
|---|---|---|---|
| Fishbrain | 76k | Fishbrain - Fishing App | Fish Spots, Maps & Forecast |
| Fishbox | 39k | Fishbox - Smart Fishing App | Spots Map, Lures, Baits, Knots |
| Fishing Points | 31k | Fishing Points: Map & Forecast | Fish Spots, Tides & Best Times |
| Fish AI | 27k | Fish AI - AI Fishing App | Spots, Forecast & Fish Log |
| BassForecast | 20k | BassForecast: Bass Fishing App | |
| FishAngler | 14k | FishAngler: Fishing App | |
| Fishing Spots (FishAngler) | 11k | Fishing Spots: Find & Fish App | |

Every one of them pays for "fishing app" in the name. Four of five subtitles contain "spots" and three contain "forecast". "Fish log" and "catch log" appear once. Nobody in the top ten uses "tides" in the name, "identifier", "solunar" or "offline".

### Terms and who holds them

| Search | Top results | Read |
|---|---|---|
| fishing app | Fishbrain, Fishbox, FishAngler, Fishing Points, Fish AI | The head term. Can't be won outright at 4 ratings, but the name must carry it to appear at all. |
| fishing | Fishbrain, then five fishing *games* | Games dilute it. Not worth chasing on its own. |
| fishing map | Fishbrain, Fishing Spots, Fishing Points, Fishbox, Navionics, onX Fish, Omnia | Crowded with map companies. Keep "maps" in keywords, don't spend title space on it. |
| fish identifier | Picture Fish (5k), Catchr (5k), FishVerify (2k), Fish101 | Small, winnable. Currents does this on device, which none of them say. "Fish ID" goes in the subtitle, "identifier" in keywords. |
| tides | Tides Near Me (163k), Tide Charts (114k), Tide Alert (45k) | Huge, but owned by tide apps. "Tides" in the subtitle picks up the long tail ("fishing tides") without pretending to compete. |
| solunar | Fishing Points, Fishing & Hunting Solunar Time, BassForecast | Niche and exactly what the forecast engine does. Keyword field. |
| bass fishing | BassForecast, Deep Dive | Species terms are how anglers actually search. "bass" and "trout" are the two biggest; "surf", "fly", "kayak" cover styles. |
| fishing times | Fishing Points' subtitle ("Best Times") | "times" in keywords combines with "fishing" in the name. |

The data behind this table was pulled from `https://itunes.apple.com/search?term=...&entity=software&country=us`. Re-run it every few months; the API rate-limits after about a dozen calls, so pause between them.

### The chosen set

Name (30/30):

```
Currents: Fishing Forecast App
```

"Fishing forecast" is the phrase the app can own: it is the first thing the app does, no top-ten app has it in the name, and Fishbrain and Fishing Points both put "forecast" in their subtitles, which tells you the search exists. "App" stays because "fishing app" is the head query and every competitor keeps it.

Subtitle, en-US (28/30):

```
Log Catches, Tides & Fish ID
```

Three things the app does that the name doesn't say, each a real search ("catch log", "fishing tides", "fish id"). It also reads as a sentence on the page.

Keywords, en-US (96/100 bytes):

```
solunar,bass,trout,angler,surf,fly,kayak,saltwater,lake,weather,moon,times,identifier,maps,spots
```

Nothing here repeats the name or subtitle. Combined phrases this unlocks: fishing times, fishing spots, fishing maps, fish identifier, bass fishing, trout fishing, surf fishing, fly fishing, kayak fishing, fishing weather, solunar forecast, moon forecast, saltwater fishing, lake fishing. "Offline", "knots", "regulations" and "licence" were cut for space; they are in the description, which converts even if it doesn't rank.

The display name on the phone stays "Currents" (`CFBundleDisplayName`); the App Store name is a separate field.

### Locales

Each storefront indexes its own localisation plus a few others. Two matter here:

| Storefront | Localisations Apple indexes | What to do |
|---|---|---|
| United States | English (U.S.) plus Spanish (Mexico) and others | Add a Spanish (Mexico) localisation whose keyword field holds *more English words*. The US store indexes them too, which is a second 100 bytes for free. Only `es-MX/keywords.txt` is provided; copy the en-US description and screenshots into that localisation when you create it, since App Store Connect requires them. |
| South Africa, United Kingdom, Ireland, Australia, Canada and others | English (U.K.), falling back to the primary | Add an English (U.K.) localisation. It gets its own subtitle and keywords, so the ZA storefront (where the current reviews come from) can rank for terms the US set has no room for: angling, carp, pike, kob, bream, estuary. UK spelling in the description (licence, favourite). |

The English (U.K.) set is in `en-GB/`. Its subtitle is "Catch Log, Tides, Spots & Maps" and its keywords add "fish" and "identifier" since that subtitle lacks "Fish ID".

The locale table is from [AppFollow's cross-localisation list](https://appfollow.io/app-store-keywords-localizations) and [AppTweak](https://www.apptweak.com/en/aso-blog/how-to-benefit-from-cross-localization-on-the-app-store). Apple's own table is on the [App Store localizations help page](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations); confirm the South Africa row there before relying on it.

## Description

`metadata/en-US/description.txt`, 3,978 of 4,000 characters. It covers every feature that shipped through 1.2.0 and the commits since, grouped under capital headers because App Store descriptions have no other formatting. The first paragraph is the only part most people see before tapping "more", so it carries the three things that set the app apart: works offline, no account, data stays on the phone.

Two facts in it to keep true:

- "Size and bag limits for South African waters": `fishing_regulations.json` currently holds 46 South African entries and nothing else. Widen the sentence when other regions land.
- "No subscription": true while there are no in-app purchases.

The voice is the README's: specific numbers, short asides, no slogans. Edit it the same way. In particular, no em or en dashes, no "not just X, it's Y", and no sign-off line; the validator rejects the dashes.

## Promotional text

`metadata/en-US/promotional_text.txt`, 149 of 170. Promotional text sits above the description and can be changed any time without submitting a build, so use it for whatever shipped most recently and swap it each release. The current one lists the four most visible things since 1.2.0.

## What's New

`metadata/en-US/release_notes.txt` is a draft for the next submission, built from the commits after the 1.2.0 release notes were written. Trim anything that turns out to have shipped in the 1.2.0 binary already.

## Screenshots

The workflow in `.github/workflows/screenshots.yml` captures five phone tabs and the watch face, then runs `scripts/caption_screenshots.py` to draw a headline and sub-line above each phone capture and publish the results to the `app-store-screenshots` branch under `captioned/`. Headlines come from `screenshots/captions.json`; the watch capture is left alone because Apple requires the exact size and there is no room.

```
make screenshots-caption        # run it locally on ios/screenshots/6.9
```

Order on the store page should match the order a first-time visitor cares about: forecast, map, log, fish ID, community, watch. That is the capture order already.

Five slots are still empty. Worth adding, in this order: the full forecast page with the factor breakdown, a tournament with the Lock Screen card, the trip planner's two-week outlook, the licence wallet, and a gear loadout. Each needs a `SCREENSHOT_TAB` value in `ScreenshotSupport.swift` that opens the right screen; the caption script needs only a new entry in `captions.json`.

## Ratings

Four ratings across all storefronts is the biggest drag on ranking. The app already asks for a review (`ios/Currents/Core/ReviewPrompt.swift`), so the thing to check is when: the best moment is right after a personal best or a first-of-species, when the confetti is still on screen, and never during onboarding or after a crash.

## Paste checklist

1. App Store Connect → the app → the version → App Information: paste `name.txt` and `subtitle.txt` for English (U.S.).
2. Same page, keywords field: paste `keywords.txt` exactly, commas and no spaces.
3. Version page: paste `promotional_text.txt`, `description.txt`, `release_notes.txt`.
4. Add localisation English (U.K.): paste the `en-GB/` files, reuse the screenshots.
5. Add localisation Spanish (Mexico): paste `es-MX/keywords.txt`, copy the en-US name, subtitle, description and screenshots.
6. Upload the `captioned/` screenshots from the `app-store-screenshots` branch in file order.
7. Run `make app-store-check` first; it fails on any over-limit field.

Name and subtitle changes only take effect with a new version submission, so pair them with the next build.

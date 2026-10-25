# App Store Connect

Everything App Store Connect asks for lives here, versioned with the code.

```
ios/AppStore/
├── README.md                     this file: research, what each field is for, where to paste it
├── captions.json                 headline above each framed screenshot (scripts/frame_screenshots.py)
├── store-art.json                the listing screenshots and the header and search results art (scripts/store_art.py)
├── preview.json                  the app preview's poster frame and music
├── preview/                      the app preview, a Remotion project (render.ts)
├── fonts/                        Inter Display for the store art (OFL)
├── store-photos/                 licensed photos behind the store art; see docs/CONTENT_RIGHTS.md
├── demo-photos/                  licensed photos seeded into the simulator for captures; never shipped
├── metadata/
│   ├── en-US/                    primary localisation: name, subtitle, keywords, promotional text,
│   │                             description, release notes, support and privacy URLs
│   ├── en-GB/                    English (U.K.): serves South Africa, the UK, Ireland, Australia
│   └── es-MX/keywords.txt        a second keyword field the US storefront also indexes
├── events/<slug>/                in-app events: name, short and long description, event.json
├── custom-product-pages/<slug>/  name, promotional text, screenshot order and keywords per page
└── game-center/                 achievements, leaderboards and challenges, each a json and image.png
```

The text files use the `fastlane deliver` layout and are uploaded by the make targets in [Publish](#publish). `make appstore-check` fails on any over-limit field.

The screenshots workflow (`.github/workflows/screenshots.yml`) captures eight phone screens and the watch, frames them with the captions, renders the in-app event media, and publishes all of it to the `app-store-screenshots` branch: `raw/`, `framed/`, `watch.png` and `events/`. The custom product pages use `framed/`. It also captures the light screens `store-art.json` needs into `stills/`, with Log catch driven through the Add menu, and composes the listing set into `store/`: `6.9/` and `6.3/` screenshots and `creative/` header, search results and universal art. `make appstore-screenshots` uploads `store/6.9` when the branch has it.

The preview video is motion design over real captures: a title card that acts out each line, then the app doing it. `ios/AppStore/preview` is a Remotion project (React, rendered frame by frame). Each app shot is built from full-size captures, the stills from the screenshots workflow plus two moments taken from the takes `.github/workflows/preview-footage.yml` records, so rows rise in one at a time, the score ring draws, bars grow, menus spring open and the camera pushes in, all at a steady 30 fps the recorder cannot give. `bun install`, then `bun render.ts [--stills <folder>] [--footage <folder>] [--music <file> | --silent]` gathers the captures into `public/`, finds the music's beats (`beats.py`) so every cut and push lands on one, renders, and encodes `ios/build/appstore-media/preview.mp4` at 886x1920, 30 fps, H.264 with stereo AAC, as Apple requires. The music is `music` in `preview.json`: "That's the Way of Life" by Michael Ramir C. from Mixkit, under the [Mixkit Stock Music Free License](https://mixkit.co/license/#musicFree), which allows online marketing ads without credit but not redistribution, so it is downloaded into `ios/build/preview-music` and never committed. `bunx remotion studio` opens the composition to scrub it frame by frame. The first frame is laid out as the poster App Store Connect shows before the preview plays (`poster` in `preview.json`).

Every slide, event image and the header share one set of lake scenes, `scenes` in `store-art.json`, drawn by `scripts/scenes.py` (hills, a ridge of pines, open water with a boat, reeds in front) at different times of day. The product page header is that scene as a 30 second loop with the Currents mark over it: `uv run scripts/render_banner.py` writes `creative/header.mp4` and its first frame, `header.png`, which is also the still Header art. The search results and universal art put the app on the same lake. Each layer drifts at its own speed and moves a whole number of repeats in the loop, so it never jumps.

`make appstore-art STILLS=<captures folder> [FOOTAGE=<clips folder>]` renders all of it into `ios/build/appstore-media`: screenshots, event images, the header video and, with footage, the preview.

## The listing

### What ranks

Apple indexes three fields for search, in this order of weight: the name, the subtitle and the 100-byte keyword field. The description, promotional text and What's New are not indexed; they convert a visitor who has already arrived. Words combine across the three fields, so "fishing" in the name plus "times" in the keywords matches a search for "fishing times". A word in the name or subtitle should not be repeated in the keywords; the repeat earns nothing. Apple matches singular and plural loosely ("tide" covers "tides") but does not stem "fishing" to "fish", so both are needed when both searches matter.

### Who holds which search

Apple publishes no volumes. The table comes from what the App Store search API returns per term, with each app's US rating count as a proxy for how contested the term is, plus the titles the funded competitors chose, which are paid-for keyword research.

| App | US ratings | Name | Subtitle |
|---|---|---|---|
| Fishbrain | 76k | Fishbrain - Fishing App | Fish Spots, Maps & Forecast |
| Fishbox | 39k | Fishbox - Smart Fishing App | Spots Map, Lures, Baits, Knots |
| Fishing Points | 31k | Fishing Points: Map & Forecast | Fish Spots, Tides & Best Times |
| Fish AI | 27k | Fish AI - AI Fishing App | Spots, Forecast & Fish Log |
| BassForecast | 20k | BassForecast: Bass Fishing App | |
| FishAngler | 14k | FishAngler: Fishing App | |

| Search | Who shows up | What it means for us |
|---|---|---|
| fishing app | Fishbrain, Fishbox, FishAngler, Fishing Points, Fish AI | The head term. "Fishing" has to be in the name to appear at all. |
| fishing forecast | Fishbrain and Fishing Points carry "forecast" in their subtitles, nobody in their name | The phrase to own; it is in our name. |
| fish identifier | Picture Fish (5k), Catchr (5k), FishVerify (2k) | Small and winnable, and we do it on device. Needs "fish" and "identifier" somewhere indexed. |
| tides | Tides Near Me (163k), Tide Charts (114k) | Owned by tide apps. Worth the long tail ("fishing tides") only. |
| fishing map | Fishbrain, Fishing Points, Navionics, onX Fish | Crowded with map companies. Keywords, not the name. |
| solunar, bass, trout, kob, carp | Fishing Points, BassForecast, regional apps | Species and method words are how anglers actually search. Cheap in the keyword field. |

Data: `https://itunes.apple.com/search?term=<term>&entity=software&country=us`. It rate-limits after a dozen calls, so pause between them.

### The fields

en-US (primary):

| Field | Value | Count |
|---|---|---|
| Name | Currents: Fishing Forecast | 26/30 |
| Subtitle | Bite times, maps and catch log | 30/30 |
| Keywords | angler,bass,carp,trout,kob,tides,solunar,lures,logbook,offline,fish,crew,tournament,spots,weather | 97/100 |

"catch" was dropped from the keyword field because the subtitle already has it; "fish" took its place so "fish identifier" and "fish log" can match.

en-GB: same name and description (already UK spelling), its own subtitle "Catch log, spots and tides" and keywords `angling,angler,carp,pike,sea,kob,bream,estuary,surf,bass,trout,solunar,moon,times,fish,identifier`. The South African storefront reads English (U.K.) first and falls back to en-US, so this is where kob, bream and estuary belong.

es-MX: the US storefront also indexes the Spanish (Mexico) localisation, so its keyword field is a second 100 bytes of English terms: `journal,tracker,planner,boat,ramps,watch,species,freshwater,saltwater,knots,regulations,identifier`. The other fields in `es-MX/` are copies of en-US because App Store Connect requires them; only the keywords differ. Reuse the en-US screenshots.

Locale sources: [AppFollow](https://appfollow.io/app-store-keywords-localizations), [AppTweak](https://www.apptweak.com/en/aso-blog/how-to-benefit-from-cross-localization-on-the-app-store), and Apple's [localisations table](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations), which has the authoritative South Africa row.

### Description, promotional text, What's New

The description groups features under short headers because the field has no other formatting. Promotional text sits above it, can be changed without a build, and should always name whatever shipped last. What's New is the draft for the next submission.

House style for all three: the README's voice, specific numbers, short asides, no slogans, no em or en dashes, no "not just X, it's Y", no closing line.

## In-app events

Events show as cards on the product page, in search results (the event name and short description are indexed), on the Today and Games tabs when Apple features them, and in the App Store's search for the event text itself. For an app with four ratings they are the one surface where a search can turn up a card as large as a top-ten app's.

Apple's rules: name 30 characters, short description 50, long description 120, a badge from Challenge, Competition, Live Event, Major Update, New Season, Premiere or Special Event, a purpose, a priority, start and end dates (an event can run at most 31 days), optional deep link, and territories. Up to ten events can be published at once. Media is a landscape event card (16:9, at least 1920x1080) and a portrait event details image (9:16, at least 1080x1920), JPG or PNG, or video. Specs: [media specifications](https://developer.apple.com/help/app-store-connect/reference/in-app-event-media-and-audio-specifications), [WWDC21 session](https://developer.apple.com/videos/play/wwdc2021/10171/).

Three events are drafted under `events/`. Each folder has the three text fields and an `event.json` with the badge, purpose, deep link, dates and which captures the media uses. `scripts/render_event_media.py` draws `event-card.png` and `event-details.png` for each from the raw captures, in the same black-background style as the framed screenshots.

| Folder | Badge | When | Deep link | Why |
|---|---|---|---|---|
| crews-and-tournaments | Major Update | The two weeks after 1.3.0 ships | currents://community | The redesign plus crews and tournaments is the biggest change since launch. "Fish With Your Crew" is the searchable name. |
| summer-bite-season | New Season | 1 to 31 December, southern-hemisphere territories | currents://map | Seasonal events get featured more often than updates. Duplicate it in March for the northern spring with the territories swapped. |
| fill-your-fishdex | Challenge | Any calendar month, re-created with new dates | currents://sessions | A reason to open the app for people who logged a few catches and stopped. |

Deep links the app handles are listed in `ios/Currents/App/ContentView.swift` (`currents://session`, `sessions`, `community`, `gear`, `licenses`, `map`, `trip/<CODE>`, `friend/<CODE>`, `crew/<CODE>`).

`make appstore-events` creates or updates each event by its `reference_name`: badge, purpose, priority, deep link, territories (`"all"` or a list of ISO alpha-3 codes), the en-US text and both images. The dates come from `schedule.rule` and `--start` (`START=` in make): `release` starts on that date, `month` takes the first whole month from it, `fixed` takes the next matching day and month. Events are left as drafts; submit them in App Store Connect. They are reviewed separately from builds and usually clear within a day.

## Custom product pages

A custom product page is a copy of the listing with its own promotional text, screenshot order, previews and (since 2025) its own keywords, reached by a link with `?ppid=<id>` or, with keywords set, directly from search. Up to 70 per app. They need review like any metadata. Apple's guide: [configure multiple product page versions](https://developer.apple.com/help/app-store-connect/create-custom-product-pages/configure-multiple-product-page-versions).

Three are drafted under `custom-product-pages/`. Each folder has `name.txt` (the internal page name, which `make appstore-pages` matches on), `promotional_text.txt`, `screenshots.txt` (the framed captures in the order to upload) and `keywords.txt` (empty when the page is link-only). Apple only lets a page use keywords that are already in the latest approved version's keyword field for that localisation; `make appstore-pages` lists the ones it cannot assign yet.

| Folder | Reached by | Leads with | Purpose |
|---|---|---|---|
| crew-invite | The invite link in `docs/open.html` when the app is not installed | Crew, leaderboard, profile | Someone tapping a crew invite does not care about the forecast yet. Paste the page id into `customPageId` in `open.html` once approved. |
| fish-id | Search, via its keywords | Catch page, logbook | Targets "fish identifier" searches, where the competition is small. |
| bite-times | Search, via its keywords | Today, lures, explore | Targets "fishing times", "solunar" and "tide" searches. |

Pages with keywords only appear in search once the page is approved and Apple decides to show it, so give them a few weeks before judging.

## Product page optimization

A test shows up to three treatments against the current page and reports which converts better. Treatments can change the icon, screenshots and app previews; the icon must already be in the binary (the alternate icons under `AppIcon-*` qualify). Tests run only while the app is live, in the localisations you pick. Apple: [overview](https://developer.apple.com/app-store/product-page-optimization/).

Worth testing, in this order, one test at a time:

1. Screenshot order. Original: the eight framed captures as captured. Treatment: crew, leaderboard and catch page first, forecast third. Tells us whether the social features or the forecast sell the app.
2. Icon. Original icon against two of the alternates (Ocean and Gold are the most different). Icon changes move install rate more than any other asset.
3. Headlines. The current captions against question headlines ("When will they bite?"), using the same captures.

Apple needs enough impressions to call a winner and the app currently gets a few hundred a week, so each test will take weeks and some will end inconclusive. Run the icon test first; it has the largest effect and so needs the least traffic.

## Promo codes

Promo codes give the app or an in-app purchase away for free, up to 100 per version. The app is free, so codes for it do nothing. The tip jar (`Core/Store/TipJar.swift`) is three consumable purchases; a code for a tip is a gift to yourself. Nothing to set up here. Reviewers and press get the TestFlight link instead.

## Game Center

The app mirrors its badges into Game Center (`Core/GameCenter/GameCenter.swift`) and submits four leaderboards. Guideline 2.5.1 lets a non-game use Game Center for virtual challenges as long as the description says so; it does, in the crew paragraph.

- `game-center/achievements/<id>/`: one per visible badge, written by `uv run scripts/render_achievement_art.py` from the badge list in `FishingLogStreak.swift`, with a 1024x1024 medallion. The ids are `badge.<title words joined by periods>`, which the app derives the same way, so a renamed badge is a new achievement. Bass Daddy and Patron stay in the app. Points scale by rarity and total 970 of Apple's 1000.
- `game-center/leaderboards/<id>/`: most fish, heaviest (grams, shown as kg), longest (millimetres, shown as cm) and fish this week, which recurs every Monday 00:00 UTC.
- `game-center/challenges/<id>/`: iOS 26 challenges on the heaviest and weekly boards, with a 3840x2160 image.

The first achievements, leaderboards and challenges go to review with an app version that contains the GameKit code.

## Asset library

The asset library is where screenshots, previews and event media are uploaded once and reused across localisations, custom product pages and tests. Upload the `framed/` set, `watch.png` and each `events/<slug>/` pair from the screenshots branch, then reference them from each page instead of uploading again.

## Publish

The listing is pushed with an App Store Connect API key (Users and Access → Integrations → App Store Connect API, role App Manager). Put `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_PATH` in the repo's `.env.local` or the environment; the key file defaults to `~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8`. Text and screenshots go through `fastlane deliver` (`ios/fastlane/Fastfile`); events, custom product pages and Game Center, which deliver does not handle, go through `scripts/asc.py`. Nothing here submits for review.

1. `make appstore-setup` once, to install fastlane into `ios/vendor/bundle`.
2. `make appstore-status` to see that the build is processed and in TestFlight.
3. `make appstore-metadata` uploads name, subtitle, keywords, description, promotional text, release notes and URLs for en-US, en-GB and es-MX to the version in `project.yml` (runs `appstore-check` first).
4. `make appstore-screenshots` replaces the screenshots in all three localisations with the `framed/` set and `watch.png` from the screenshots branch. `STORE_ART_DIR=<folder>` uploads a local set of 1320x2868 PNGs in place of `framed/`, such as the `6.9` folder `scripts/store_art.py` writes; `watch.png` still comes from the branch.
5. `make appstore-media`, then `make appstore-media APPLY=1`. It places `preview.mp4`, the header (`creative/header.mp4`, or `header.png` when there is no video) and `creative/search.png` from `ios/build/appstore-media` on every localisation of the version being prepared, through the asset library. Each file is checked against Apple's specs first, and a file already in the library is not uploaded again.
6. `make appstore-events START=<launch date>` shows what would change; `make appstore-events START=<launch date> APPLY=1` writes it.
7. `make appstore-pages`, then `make appstore-pages APPLY=1`. It prints each page id.
8. `make appstore-gamecenter`, then `make appstore-gamecenter APPLY=1`. It turns on the Game Center capability for the App ID and Game Center for the app and the version being prepared, and creates the achievements, leaderboards and challenges with their images in all three localisations.
9. In App Store Connect, submit the version, the events, the custom product pages and the Game Center items for review.

`make appstore-upload` runs steps 3 to 8 in one go from `ios/build/appstore-media`: a dry run, then `make appstore-upload START=<launch date> APPLY=1` to write it. Without `START` the events keep their text and dates and only their images change. fastlane deliver has no dry run, so the dry run checks the text and lists the screenshots in upload order without sending them.

To swap every image and video without touching any text (listing screenshots, preview, header, search results, event images and the custom product pages' screenshots), render with `make appstore-art`, then `make appstore-images` for a dry run and `make appstore-images APPLY=1` to write it. A custom product page in review is skipped until the review finishes.

Still by hand:

- Paste the crew-invite page id printed in step 7 into `customPageId` in `docs/open.html` once the page is approved.
- After the version is live, start the icon test under Product Page Optimization.

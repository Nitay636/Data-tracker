import Foundation

public enum AppCategory: String, CaseIterable, Sendable {
    case video, music, social, messaging, games, productivity, shopping, travel, news, ai, cloud, ads, system, other

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .video: return "play.rectangle.fill"
        case .music: return "music.note"
        case .social: return "person.2.fill"
        case .messaging: return "message.fill"
        case .games: return "gamecontroller.fill"
        case .productivity: return "briefcase.fill"
        case .shopping: return "cart.fill"
        case .travel: return "car.fill"
        case .news: return "newspaper.fill"
        case .ai: return "sparkles"
        case .cloud: return "icloud.fill"
        case .ads: return "megaphone.fill"
        case .system: return "gearshape.fill"
        case .other: return "app.fill"
        }
    }

    /// Hex RGB color used for the icon background.
    public var colorHex: String {
        switch self {
        case .video: return "E5484D"
        case .music: return "D6409F"
        case .social: return "8E4EC6"
        case .messaging: return "30A46C"
        case .games: return "F76B15"
        case .productivity: return "0090FF"
        case .shopping: return "FFB224"
        case .travel: return "12A594"
        case .news: return "6E56CF"
        case .ai: return "3E63DD"
        case .cloud: return "0588F0"
        case .ads: return "978365"
        case .system: return "8B8D98"
        case .other: return "687076"
        }
    }
}

public struct AppDefinition: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var category: AppCategory
    /// Domain suffixes. `googlevideo.com` matches `googlevideo.com` and every sub-domain of it.
    public var domains: [String]

    public init(id: String, name: String, category: AppCategory, domains: [String]) {
        self.id = id
        self.name = name
        self.category = category
        self.domains = domains
    }
}

/// Built-in mapping of domains to popular apps. Users can add their own assignments on top.
public enum AppCatalog {
    public static let systemID = "system.ios"

    public static let all: [AppDefinition] = [
        // MARK: Apple / system
        AppDefinition(id: systemID, name: "iOS & System Services", category: .system, domains: [
            "apple.com", "cdn-apple.com", "aaplimg.com", "apple-dns.net", "apple-dns.cn", "push.apple.com",
            "mesu.apple.com", "gs.apple.com", "gsp.apple.com", "ls.apple.com", "smoot.apple.com",
            "apple-mapkit.com", "apple.map.fastly.net", "itunes-apple.com.akadns.net", "captive.apple.com",
            "ess.apple.com", "guzzoni.apple.com", "weatherkit.apple.com", "apple-relay.apple.com"
        ]),
        AppDefinition(id: "apple.appstore", name: "App Store & Apple Media", category: .system, domains: [
            "itunes.apple.com", "apps.apple.com", "mzstatic.com", "appstore.com", "music.apple.com",
            "tv.apple.com", "podcasts.apple.com", "books.apple.com", "apple.news", "news.apple.com"
        ]),
        AppDefinition(id: "apple.icloud", name: "iCloud", category: .cloud, domains: [
            "icloud.com", "icloud-content.com", "apple-cloudkit.com", "icloud.apple.com", "me.com", "mac.com"
        ]),

        // MARK: Video
        AppDefinition(id: "youtube", name: "YouTube", category: .video, domains: [
            "youtube.com", "googlevideo.com", "ytimg.com", "youtube-nocookie.com", "youtubei.googleapis.com",
            "youtube.googleapis.com", "yt.be", "youtu.be", "ggpht.com"
        ]),
        AppDefinition(id: "netflix", name: "Netflix", category: .video, domains: [
            "netflix.com", "nflxvideo.net", "nflximg.net", "nflximg.com", "nflxext.com", "nflxso.net", "netflix.net"
        ]),
        AppDefinition(id: "primevideo", name: "Prime Video", category: .video, domains: [
            "primevideo.com", "aiv-cdn.net", "aiv-delivery.net", "pv-cdn.net", "atv-ps.amazon.com",
            "atv-ext.amazon.com", "amazonvideo.com"
        ]),
        AppDefinition(id: "disneyplus", name: "Disney+", category: .video, domains: [
            "disneyplus.com", "disney-plus.net", "dssott.com", "bamgrid.com", "disneystreaming.com", "dssedge.com"
        ]),
        AppDefinition(id: "max", name: "Max", category: .video, domains: [
            "max.com", "hbomax.com", "hbo.com", "hbomaxcdn.com", "discomax.com"
        ]),
        AppDefinition(id: "hulu", name: "Hulu", category: .video, domains: ["hulu.com", "hulustream.com", "huluim.com"]),
        AppDefinition(id: "paramountplus", name: "Paramount+", category: .video, domains: [
            "paramountplus.com", "cbsivideo.com", "cbsaavideo.com", "pplusstatic.com"
        ]),
        AppDefinition(id: "peacock", name: "Peacock", category: .video, domains: ["peacocktv.com", "peacock.com"]),
        AppDefinition(id: "twitch", name: "Twitch", category: .video, domains: ["twitch.tv", "ttvnw.net", "jtvnw.net", "twitchcdn.net"]),
        AppDefinition(id: "kick", name: "Kick", category: .video, domains: ["kick.com"]),
        AppDefinition(id: "vimeo", name: "Vimeo", category: .video, domains: ["vimeo.com", "vimeocdn.com"]),
        AppDefinition(id: "crunchyroll", name: "Crunchyroll", category: .video, domains: ["crunchyroll.com", "vrv.co"]),
        AppDefinition(id: "dazn", name: "DAZN", category: .video, domains: ["dazn.com", "dazn-api.com", "indazn.com"]),
        AppDefinition(id: "espn", name: "ESPN", category: .video, domains: ["espn.com", "espncdn.com", "espn.net"]),
        AppDefinition(id: "plex", name: "Plex", category: .video, domains: ["plex.tv", "plex.direct"]),

        // MARK: Music & audio
        AppDefinition(id: "spotify", name: "Spotify", category: .music, domains: [
            "spotify.com", "scdn.co", "spotifycdn.com", "spotifycdn.net", "spotilocal.com", "pscdn.co", "spotify.design"
        ]),
        AppDefinition(id: "soundcloud", name: "SoundCloud", category: .music, domains: ["soundcloud.com", "sndcdn.com"]),
        AppDefinition(id: "deezer", name: "Deezer", category: .music, domains: ["deezer.com", "dzcdn.net"]),
        AppDefinition(id: "pandora", name: "Pandora", category: .music, domains: ["pandora.com", "p-cdn.com", "p-cdn.us"]),
        AppDefinition(id: "tidal", name: "TIDAL", category: .music, domains: ["tidal.com", "tidalhifi.com"]),
        AppDefinition(id: "audible", name: "Audible", category: .music, domains: ["audible.com", "audible.co.uk"]),
        AppDefinition(id: "shazam", name: "Shazam", category: .music, domains: ["shazam.com"]),

        // MARK: Social
        AppDefinition(id: "instagram", name: "Instagram", category: .social, domains: ["instagram.com", "cdninstagram.com", "ig.me"]),
        AppDefinition(id: "facebook", name: "Facebook", category: .social, domains: [
            "facebook.com", "fbcdn.net", "facebook.net", "fb.com", "fbsbx.com", "fb.me", "fbpigeon.com"
        ]),
        AppDefinition(id: "threads", name: "Threads", category: .social, domains: ["threads.net", "threads.com"]),
        AppDefinition(id: "tiktok", name: "TikTok", category: .social, domains: [
            "tiktok.com", "tiktokv.com", "tiktokv.us", "tiktokcdn.com", "tiktokcdn-us.com", "tiktokcdn-eu.com",
            "byteoversea.com", "ibytedtos.com", "ibyteimg.com", "muscdn.com", "ttwstatic.com", "tiktokw.us",
            "byteoversea.net", "tik-tokapi.com"
        ]),
        AppDefinition(id: "x", name: "X (Twitter)", category: .social, domains: ["twitter.com", "x.com", "twimg.com", "t.co", "pscp.tv"]),
        AppDefinition(id: "snapchat", name: "Snapchat", category: .social, domains: [
            "snapchat.com", "sc-cdn.net", "snap-dev.net", "snapkit.com", "sc-static.net", "snapads.com", "sc-gw.com",
            "sc-prod.net", "snap.com"
        ]),
        AppDefinition(id: "reddit", name: "Reddit", category: .social, domains: ["reddit.com", "redd.it", "redditmedia.com", "redditstatic.com"]),
        AppDefinition(id: "pinterest", name: "Pinterest", category: .social, domains: ["pinterest.com", "pinimg.com", "pin.it"]),
        AppDefinition(id: "linkedin", name: "LinkedIn", category: .social, domains: ["linkedin.com", "licdn.com", "lnkd.in"]),
        AppDefinition(id: "tumblr", name: "Tumblr", category: .social, domains: ["tumblr.com"]),
        AppDefinition(id: "bluesky", name: "Bluesky", category: .social, domains: ["bsky.app", "bsky.social", "bsky.network"]),
        AppDefinition(id: "tinder", name: "Tinder", category: .social, domains: ["tinder.com", "gotinder.com", "tindersparks.com"]),
        AppDefinition(id: "bumble", name: "Bumble", category: .social, domains: ["bumble.com", "bumbcdn.com", "bumble.app"]),
        AppDefinition(id: "hinge", name: "Hinge", category: .social, domains: ["hinge.co"]),
        AppDefinition(id: "strava", name: "Strava", category: .social, domains: ["strava.com", "strava.cdn.com"]),

        // MARK: Messaging & calls
        AppDefinition(id: "whatsapp", name: "WhatsApp", category: .messaging, domains: ["whatsapp.net", "whatsapp.com", "wa.me"]),
        AppDefinition(id: "messenger", name: "Messenger", category: .messaging, domains: ["messenger.com", "m.me"]),
        AppDefinition(id: "telegram", name: "Telegram", category: .messaging, domains: [
            "telegram.org", "t.me", "telegram.me", "cdn-telegram.org", "telesco.pe", "tdesktop.com"
        ]),
        AppDefinition(id: "signal", name: "Signal", category: .messaging, domains: ["signal.org", "whispersystems.org", "signal.art", "signal.group"]),
        AppDefinition(id: "viber", name: "Viber", category: .messaging, domains: ["viber.com"]),
        AppDefinition(id: "discord", name: "Discord", category: .messaging, domains: [
            "discord.com", "discord.gg", "discordapp.com", "discordapp.net", "discord.media", "discordcdn.com"
        ]),
        AppDefinition(id: "wechat", name: "WeChat", category: .messaging, domains: ["wechat.com", "weixin.qq.com", "wx.qq.com", "wechatapp.com"]),
        AppDefinition(id: "line", name: "LINE", category: .messaging, domains: ["line.me", "line-scdn.net", "line-apps.com", "naver.jp"]),
        AppDefinition(id: "skype", name: "Skype", category: .messaging, domains: ["skype.com", "skypeassets.com"]),
        AppDefinition(id: "zoom", name: "Zoom", category: .messaging, domains: ["zoom.us", "zoom.com", "zoomgov.com", "zoomcdn.com"]),
        AppDefinition(id: "teams", name: "Microsoft Teams", category: .messaging, domains: [
            "teams.microsoft.com", "teams.live.com", "teams.cdn.office.net", "lync.com"
        ]),
        AppDefinition(id: "webex", name: "Webex", category: .messaging, domains: ["webex.com", "wbx2.com"]),
        AppDefinition(id: "slack", name: "Slack", category: .messaging, domains: ["slack.com", "slack-edge.com", "slack-msgs.com", "slack-imgs.com", "slack-files.com"]),

        // MARK: Google & Microsoft
        AppDefinition(id: "google", name: "Google", category: .productivity, domains: [
            "google.com", "gstatic.com", "googleapis.com", "googleusercontent.com", "gvt1.com", "gvt2.com",
            "gvt3.com", "google.co.uk", "google.co.il", "google.de", "google.fr", "googletagmanager.com", "goo.gl",
            "withgoogle.com", "googlezip.net"
        ]),
        AppDefinition(id: "gmail", name: "Gmail", category: .productivity, domains: ["mail.google.com", "gmail.com", "inbox.google.com"]),
        AppDefinition(id: "googlemaps", name: "Google Maps", category: .travel, domains: [
            "maps.google.com", "maps.googleapis.com", "maps.gstatic.com", "mt.google.com", "khms.google.com"
        ]),
        AppDefinition(id: "googledrive", name: "Google Drive & Docs", category: .cloud, domains: [
            "drive.google.com", "docs.google.com", "sheets.google.com", "slides.google.com", "drive.googleapis.com",
            "docs.googleapis.com"
        ]),
        AppDefinition(id: "googlephotos", name: "Google Photos", category: .cloud, domains: ["photos.google.com", "photos.googleapis.com", "photoslibrary.googleapis.com"]),
        AppDefinition(id: "googlemeet", name: "Google Meet", category: .messaging, domains: ["meet.google.com", "meetings.googleapis.com"]),
        AppDefinition(id: "gemini", name: "Gemini", category: .ai, domains: ["gemini.google.com", "bard.google.com", "generativelanguage.googleapis.com"]),
        AppDefinition(id: "microsoft365", name: "Microsoft 365 & Outlook", category: .productivity, domains: [
            "office.com", "office.net", "office365.com", "outlook.com", "outlook.office365.com", "sharepoint.com",
            "microsoft.com", "microsoftonline.com", "msftauth.net", "live.com"
        ]),
        AppDefinition(id: "onedrive", name: "OneDrive", category: .cloud, domains: ["onedrive.com", "onedrive.live.com", "1drv.com", "1drv.ms"]),

        // MARK: Productivity & cloud
        AppDefinition(id: "dropbox", name: "Dropbox", category: .cloud, domains: ["dropbox.com", "dropboxapi.com", "dropboxusercontent.com", "dropboxstatic.com"]),
        AppDefinition(id: "notion", name: "Notion", category: .productivity, domains: ["notion.so", "notion.com", "notion.site", "notion-static.com"]),
        AppDefinition(id: "github", name: "GitHub", category: .productivity, domains: ["github.com", "githubusercontent.com", "githubassets.com", "github.io"]),
        AppDefinition(id: "figma", name: "Figma", category: .productivity, domains: ["figma.com"]),
        AppDefinition(id: "canva", name: "Canva", category: .productivity, domains: ["canva.com", "canva.cn"]),
        AppDefinition(id: "trello", name: "Trello", category: .productivity, domains: ["trello.com", "trellocdn.com"]),
        AppDefinition(id: "evernote", name: "Evernote", category: .productivity, domains: ["evernote.com"]),
        AppDefinition(id: "adobe", name: "Adobe", category: .productivity, domains: ["adobe.com", "adobe.io", "adobelogin.com", "behance.net"]),
        AppDefinition(id: "duolingo", name: "Duolingo", category: .productivity, domains: ["duolingo.com"]),
        AppDefinition(id: "yahoo", name: "Yahoo", category: .productivity, domains: ["yahoo.com", "yimg.com", "yahooapis.com"]),
        AppDefinition(id: "proton", name: "Proton", category: .productivity, domains: ["proton.me", "protonmail.com", "protonmail.ch"]),

        // MARK: AI
        AppDefinition(id: "chatgpt", name: "ChatGPT", category: .ai, domains: ["openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com"]),
        AppDefinition(id: "claude", name: "Claude", category: .ai, domains: ["claude.ai", "anthropic.com", "claudeusercontent.com"]),
        AppDefinition(id: "perplexity", name: "Perplexity", category: .ai, domains: ["perplexity.ai", "pplx.ai"]),
        AppDefinition(id: "copilot", name: "Copilot", category: .ai, domains: ["copilot.microsoft.com", "bing.com", "bing.net"]),

        // MARK: Shopping & payments
        AppDefinition(id: "amazon", name: "Amazon", category: .shopping, domains: [
            "amazon.com", "amazon.co.uk", "amazon.de", "amazon.fr", "amazon.it", "amazon.es", "amazon.ca",
            "amazon.co.jp", "amazon.in", "amazon.com.au", "media-amazon.com", "ssl-images-amazon.com", "a2z.com",
            "amazon.dev"
        ]),
        AppDefinition(id: "ebay", name: "eBay", category: .shopping, domains: ["ebay.com", "ebayimg.com", "ebaystatic.com", "ebay.co.uk", "ebay.de"]),
        AppDefinition(id: "aliexpress", name: "AliExpress", category: .shopping, domains: ["aliexpress.com", "aliexpress.us", "alicdn.com", "aliexpress.ru"]),
        AppDefinition(id: "temu", name: "Temu", category: .shopping, domains: ["temu.com", "kwcdn.com"]),
        AppDefinition(id: "shein", name: "SHEIN", category: .shopping, domains: ["shein.com", "ltwebstatic.com", "sheinsz.com"]),
        AppDefinition(id: "etsy", name: "Etsy", category: .shopping, domains: ["etsy.com", "etsystatic.com"]),
        AppDefinition(id: "paypal", name: "PayPal", category: .shopping, domains: ["paypal.com", "paypalobjects.com", "paypal.me"]),
        AppDefinition(id: "venmo", name: "Venmo", category: .shopping, domains: ["venmo.com"]),

        // MARK: Travel & maps
        AppDefinition(id: "waze", name: "Waze", category: .travel, domains: ["waze.com"]),
        AppDefinition(id: "uber", name: "Uber", category: .travel, domains: ["uber.com", "ubereats.com", "uberinternal.com", "ubr.to"]),
        AppDefinition(id: "lyft", name: "Lyft", category: .travel, domains: ["lyft.com", "lyft.net"]),
        AppDefinition(id: "airbnb", name: "Airbnb", category: .travel, domains: ["airbnb.com", "muscache.com", "airbnb.co.uk"]),
        AppDefinition(id: "booking", name: "Booking.com", category: .travel, domains: ["booking.com", "bstatic.com"]),
        AppDefinition(id: "moovit", name: "Moovit", category: .travel, domains: ["moovitapp.com", "moovit.com"]),
        AppDefinition(id: "wolt", name: "Wolt", category: .travel, domains: ["wolt.com", "woltapi.com"]),
        AppDefinition(id: "doordash", name: "DoorDash", category: .travel, domains: ["doordash.com", "doordash.net"]),

        // MARK: News
        AppDefinition(id: "nytimes", name: "The New York Times", category: .news, domains: ["nytimes.com", "nyt.com"]),
        AppDefinition(id: "cnn", name: "CNN", category: .news, domains: ["cnn.com", "cnn.io", "turner.com"]),
        AppDefinition(id: "bbc", name: "BBC", category: .news, domains: ["bbc.co.uk", "bbci.co.uk", "bbc.com"]),
        AppDefinition(id: "guardian", name: "The Guardian", category: .news, domains: ["theguardian.com", "guim.co.uk"]),

        // MARK: Games
        AppDefinition(id: "roblox", name: "Roblox", category: .games, domains: ["roblox.com", "rbxcdn.com", "rbx.com"]),
        AppDefinition(id: "epic", name: "Fortnite / Epic Games", category: .games, domains: ["epicgames.com", "epicgames.dev", "fortnite.com", "unrealengine.com"]),
        AppDefinition(id: "supercell", name: "Supercell games", category: .games, domains: ["supercell.com", "supercell.net", "clashofclans.com", "brawlstars.com"]),
        AppDefinition(id: "pokemongo", name: "Pokémon GO", category: .games, domains: ["nianticlabs.com", "pokemongolive.com", "nianticspatial.com"]),
        AppDefinition(id: "king", name: "Candy Crush (King)", category: .games, domains: ["king.com", "midasplayer.net"]),
        AppDefinition(id: "pubg", name: "PUBG Mobile", category: .games, domains: ["pubgmobile.com", "igamecj.com", "proximabeta.com"]),
        AppDefinition(id: "codm", name: "Call of Duty", category: .games, domains: ["activision.com", "callofduty.com", "demonware.net"]),
        AppDefinition(id: "hoyoverse", name: "HoYoverse games", category: .games, domains: ["hoyoverse.com", "mihoyo.com", "hoyolab.com"]),
        AppDefinition(id: "minecraft", name: "Minecraft / Xbox", category: .games, domains: ["minecraft.net", "mojang.com", "xboxlive.com", "xbox.com"]),

        // MARK: Ads & analytics (inside many apps)
        AppDefinition(id: "ads", name: "Ads & Analytics", category: .ads, domains: [
            "doubleclick.net", "googlesyndication.com", "googleadservices.com", "app-measurement.com",
            "google-analytics.com", "crashlytics.com", "appsflyer.com", "appsflyersdk.com", "adjust.com",
            "branch.io", "applovin.com", "applvn.com", "unityads.unity3d.com", "ironsrc.com", "ironsrc.mobi",
            "inmobi.com", "vungle.com", "chartboost.com", "adcolony.com", "moloco.com", "liftoff.io", "taboola.com",
            "outbrain.com", "criteo.com", "amazon-adsystem.com", "scorecardresearch.com", "mixpanel.com",
            "amplitude.com", "segment.io", "braze.com", "onesignal.com", "sentry.io", "bugsnag.com"
        ])
    ]

    public static let byID: [String: AppDefinition] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}

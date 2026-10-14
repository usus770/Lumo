import XCTest
@testable import Lumo

final class TitleParserTests: XCTestCase {
    
    func testTitleCleaning() {
        let cases: [(raw: String, expected: String, isLive: Bool)] = [
            ("Song Title (Official Video)", "Song Title", false),
            ("Song Title [Official Music Video]", "Song Title", false),
            ("Artist - Song (Official Audio)", "Artist - Song", false),
            ("Artist - Song (Lyrics)", "Artist - Song", false),
            ("Artist - Song [Lyric Video]", "Artist - Song", false),
            ("Artist - Song (HD)", "Artist - Song", false),
            ("Artist - Song (HQ) [4K]", "Artist - Song", false),
            ("Artist - Song (Live)", "Artist - Song", true),
            ("Artist - Song (Prod. by Producer)", "Artist - Song", false),
            ("Artist - Song [Explicit]", "Artist - Song", false),
            ("Artist - Song (Clean)", "Artist - Song", false),
            ("Artist - Song (Official Video) [1080p]", "Artist - Song [1080p]", false),
            ("Song Title - aBcDeF12345", "Song Title", false),
            ("Song Title [aBcDeF12345]", "Song Title", false),
            ("Artist - Song.mp3", "Artist - Song", false),
            ("Artist - Song.m4a", "Artist - Song", false),
            ("Artist - Song_with_underscores", "Artist - Song with underscores", false),
            ("Artist - Song (Slowed + Reverb)", "Artist - Song", false),
            ("Artist - Song (Nightcore)", "Artist - Song", false),
        ]
        
        for c in cases {
            let result = TitleCleaner.clean(c.raw)
            XCTAssertEqual(result.cleanedString, c.expected, "Failed to clean: \(c.raw)")
            XCTAssertEqual(result.isLive, c.isLive, "Failed live flag for: \(c.raw)")
        }
    }
    
    func testTitleParsing() {
        struct Case {
            let raw: String
            let expectedArtist: String
            let expectedTitle: String
            let expectedFeatured: [String]
        }
        
        let cases: [Case] = [
            Case(raw: "The Beatles - Hey Jude", expectedArtist: "The Beatles", expectedTitle: "Hey Jude", expectedFeatured: []),
            Case(raw: "Kanye West - Stronger (Official Video)", expectedArtist: "Kanye West", expectedTitle: "Stronger", expectedFeatured: []),
            Case(raw: "Eminem – Lose Yourself", expectedArtist: "Eminem", expectedTitle: "Lose Yourself", expectedFeatured: []),
            Case(raw: "Daft Punk — Get Lucky", expectedArtist: "Daft Punk", expectedTitle: "Get Lucky", expectedFeatured: []),
            Case(raw: "Drake - One Dance ft. Wizkid & Kyla", expectedArtist: "Drake", expectedTitle: "One Dance", expectedFeatured: ["Wizkid", "Kyla"]),
            Case(raw: "Calvin Harris - Slide feat. Frank Ocean, Migos", expectedArtist: "Calvin Harris", expectedTitle: "Slide", expectedFeatured: ["Frank Ocean", "Migos"]),
            Case(raw: "Snoop Dogg - Drop It Like It's Hot (feat. Pharrell)", expectedArtist: "Snoop Dogg", expectedTitle: "Drop It Like It's Hot", expectedFeatured: ["Pharrell"]),
            Case(raw: "Marshmello x Anne-Marie - FRIENDS", expectedArtist: "Marshmello", expectedTitle: "FRIENDS", expectedFeatured: ["Anne-Marie"]),
            Case(raw: "Travis Scott : SICKO MODE", expectedArtist: "Travis Scott", expectedTitle: "SICKO MODE", expectedFeatured: []),
            Case(raw: "SICKO MODE | Travis Scott", expectedArtist: "Travis Scott", expectedTitle: "SICKO MODE", expectedFeatured: []),
            Case(raw: "YOASOBI「アイドル」", expectedArtist: "YOASOBI", expectedTitle: "アイドル", expectedFeatured: []),
            Case(raw: "Kenshi Yonezu『KICK BACK』", expectedArtist: "Kenshi Yonezu", expectedTitle: "KICK BACK", expectedFeatured: []),
            Case(raw: "The Weeknd \"Blinding Lights\"", expectedArtist: "The Weeknd", expectedTitle: "Blinding Lights", expectedFeatured: []),
            Case(raw: "Shape of You by Ed Sheeran", expectedArtist: "Ed Sheeran", expectedTitle: "Shape of You", expectedFeatured: []),
            Case(raw: "Bohemian Rhapsody", expectedArtist: "Queen", expectedTitle: "Bohemian Rhapsody", expectedFeatured: []),
        ]
        
        for c in cases {
            let cleaned = TitleCleaner.clean(c.raw).cleanedString
            let uploader = c.expectedArtist == "Queen" ? "Queen - Topic" : nil
            let candidates = TitleParser.parse(cleanedString: cleaned, uploader: uploader)
            
            XCTAssertFalse(candidates.isEmpty, "No candidates for \(c.raw)")
            if let best = candidates.first {
                XCTAssertEqual(best.artist, c.expectedArtist, "Wrong artist for \(c.raw)")
                XCTAssertEqual(best.title, c.expectedTitle, "Wrong title for \(c.raw)")
                
                for expectedFeat in c.expectedFeatured {
                    XCTAssertTrue(best.featuredArtists.contains(where: { $0.contains(expectedFeat) }), "Missing featured \(expectedFeat) in \(c.raw)")
                }
            }
        }
    }
}

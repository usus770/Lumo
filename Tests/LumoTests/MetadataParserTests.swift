import XCTest
@testable import Lumo

final class MetadataParserTests: XCTestCase {
    
    func testArtistTitleOrder() {
        let candidates1 = TitleParser.parse(cleanedString: "mgk - glass house (feat. Naomi Wild)")
        XCTAssertEqual(candidates1.first?.artist, "mgk")
        XCTAssertEqual(candidates1.first?.title, "glass house")
        XCTAssertEqual(candidates1.first?.featuredArtists, ["Naomi Wild"])
        
        let candidates2 = TitleParser.parse(cleanedString: "mgk - in these walls (my house)")
        XCTAssertEqual(candidates2.first?.artist, "mgk")
        XCTAssertEqual(candidates2.first?.title, "in these walls (my house)")
        
        let candidates3 = TitleParser.parse(cleanedString: "mgk - roll the windows up")
        XCTAssertEqual(candidates3.first?.artist, "mgk")
        XCTAssertEqual(candidates3.first?.title, "roll the windows up")
        
        // Rockabye
        let candidates4 = TitleParser.parse(cleanedString: "Rockabye feat Sean Paul & Anne-Marie")
        XCTAssertEqual(candidates4.first?.title, "Rockabye")
        XCTAssertEqual(candidates4.first?.artist, "")
        XCTAssertTrue(candidates4.first?.featuredArtists.contains("Sean Paul") == true)
        
        // SEVENTEEN
        let clean5 = TitleCleaner.clean("[MV] SEVENTEEN(세븐틴) - MAESTRO").cleanedString
        let candidates5 = TitleParser.parse(cleanedString: clean5)
        XCTAssertEqual(candidates5.first?.artist, "SEVENTEEN(세븐틴)")
        XCTAssertEqual(candidates5.first?.title, "MAESTRO")
    }
}

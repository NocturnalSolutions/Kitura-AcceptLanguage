import XCTest
import Kitura
import KituraNet
@testable import KituraAcceptLanguage

class KituraAcceptLanguageTests: XCTestCase {

    let router = KituraAcceptLanguageTests.setupRouter()

    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
//        XCTAssertEqual(KituraAcceptLanguage().text, "Hello, World!")
    }

    func testNoReqHeader() {
        performServerTest(router: router) { expectation in
            self.performGetWithAcceptLanguage("/accept-lang", acceptLanguage: nil, callback: { response in
                XCTAssertEqual(AcceptLanguage.NegotiationStatus.NoAcceptLanguageHeader.hashValue, Int(response!.headers["X-Negotiation-Status"]!.first!), "Mishandled missing Accept-Language header")
                expectation.fulfill()
            })
        }
    }

    func testSimpleNegotiation() {
        performServerTest(router: router) { expectation in
            self.performGetWithAcceptLanguage("/accept-lang", acceptLanguage: "no, ja", callback: { response in
                XCTAssertEqual(response!.headers["X-Langcode"]!.first!, "ja", "Did not negotiate match")
                XCTAssertNotNil(response!.headers["Content-Language"], "Did not add Content-Language header")
                if let clHeader = response!.headers["Content-Language"] {
                    XCTAssertEqual(clHeader.first!, "ja", "Did not properly set Content-Language header")
                }
            })
            self.performGetWithAcceptLanguage("/accept-lang", acceptLanguage: "no, fi, sv", callback: { response in
                XCTAssertEqual(AcceptLanguage.NegotiationStatus.NoMatch.hashValue, Int(response!.headers["X-Negotiation-Status"]!.first!), "Did not recognize failure to match")
                XCTAssertEqual(response!.headers["X-Langcode"]!.first!, "en", "Did not fall back properly on no match")
            })
            expectation.fulfill()
        }
    }

    func testNegotiationWithQuality() {
        performServerTest(router: router) { expectation in
            self.performGetWithAcceptLanguage("/accept-lang", acceptLanguage: "zh-hans, ja;q=0.9, en;q=0.8", callback: { response in
                XCTAssertEqual(response!.headers["X-Langcode"]!.first!, "ja", "Did not negotiate match factoring quality scores properly")
                XCTAssertEqual(response!.headers["X-Match-Quality"]!.first!, "0.9", "Did not calculate match quality correctly")
                
            })
            expectation.fulfill()
        }
    }

    func testNoResHeader() {
        performServerTest(router: router) { expectation in
            self.performGetWithAcceptLanguage("/accept-lang-no-header", acceptLanguage: "zh-hans", callback: { response in
                XCTAssertEqual(response!.headers["X-Langcode"]!.first!, "zh-hans", "Did not negotiate match when not sending Content-Language header")
                XCTAssertNil(response!.headers["Content-Language"], "Content-Langauge header sent when it should not have been")
            })
            expectation.fulfill()
        }
    }

    func testOddities() {
        performServerTest(router: router) { expectation in
            self.performGetWithAcceptLanguage("/accept-lang-failure", acceptLanguage: "ja", callback: { response in
                XCTAssertEqual(Int(response!.headers["X-Negotiation-Status"]!.first!), AcceptLanguage.NegotiationStatus.NoMatch.hashValue, "Impossible match")
            })
            self.performGetWithAcceptLanguage("/accept-lang", acceptLanguage: "qwert;1=, q=yiop, ;;;,,, asdf;q=4, en;q=0, ja, ..zxcv", callback: { response in
                guard response!.headers["X-Langcode"] != nil else {
                    XCTFail("Failed to make a match through garbage in the Accept-Language header")
                    return
                }
                XCTAssertEqual(response!.headers["X-Langcode"]!.first!, "ja", "Failed to make a match through garbage in the Accept-Language header")
            })
            expectation.fulfill()
        }}

    static var allTests = [
        ("testNoReqHeader", testNoReqHeader),
        ("testSimpleNegotiation", testSimpleNegotiation),
        ("testNegotiationWithQuality", testNegotiationWithQuality),
        ("testNoResHeader", testNoResHeader),
        ("testOddities", testOddities),
    ]

    static func setupRouter() -> Router {
        let router = Router()

        let routes = [
            "/accept-lang": AcceptLanguage(["en", "ja"]),
            "/accept-lang-failure": AcceptLanguage([]),
            "/accept-lang-no-header": AcceptLanguage(["en", "zh-hans"], sendContentLanguageHeader: false)
        ]

        for (path, al) in routes {
            router.get(path, middleware: al)
            router.get(path) { _, response, next in
                response.headers["X-Negotiation-Status"] = String(al.negotiationStatus.hashValue)
                if let lang = al.negotiatedLanguage {
                    response.headers["X-Langcode"] = lang.langcode
                    response.headers["X-Match-Quality"] = String(lang.matchQuality)

                }
                next()
            }
        }
        return router
    }

    // Ripped off from the Kitura-CredentialsHTTP tests.
    func performServerTest(router: ServerDelegate, asyncTasks: @escaping (XCTestExpectation) -> Void...) {
        do {
            let server = try HTTPServer.listen(on: 8090, delegate: router)
            let requestQueue = DispatchQueue(label: "Request queue")

            for (index, asyncTask) in asyncTasks.enumerated() {
                let expectation = self.expectation(index)
                requestQueue.async {
                    asyncTask(expectation)
                }
            }

            waitExpectation(timeout: 10) { error in
                // blocks test until request completes
                server.stop()
                XCTAssertNil(error);
            }
        } catch {
            XCTFail("Error: \(error)")
        }
    }

    func performRequest(method: String, host: String = "localhost", path: String, callback: @escaping ClientRequest.Callback, headers: [String: String]? = nil, requestModifier: ((ClientRequest) -> Void)? = nil) {
        var allHeaders = [String: String]()
        if  let headers = headers  {
            for  (headerName, headerValue) in headers  {
                allHeaders[headerName] = headerValue
            }
        }
        allHeaders["Content-Type"] = "text/plain"
        let options: [ClientRequest.Options] =
            [.method(method), .hostname(host), .port(8090), .path(path), .headers(allHeaders)]
        let req = HTTP.request(options, callback: callback)
        if let requestModifier = requestModifier {
            requestModifier(req)
        }
        req.end()
    }

    func expectation(_ index: Int) -> XCTestExpectation {
        let expectationDescription = "\(type(of: self))-\(index)"
        return self.expectation(description: expectationDescription)
    }

    func waitExpectation(timeout t: TimeInterval, handler: XCWaitCompletionHandler?) {
        self.waitForExpectations(timeout: t, handler: handler)
    }

    func performGetWithAcceptLanguage(_ path: String, acceptLanguage: String?, callback: @escaping ClientRequest.Callback) {
        var headers: [String : String] = [:]
        if let acceptLanguage = acceptLanguage {
            headers["Accept-Language"] = acceptLanguage
        }
        performRequest(method: "get", host: "localhost", path: path, callback: callback, headers: headers, requestModifier: nil)
    }

}

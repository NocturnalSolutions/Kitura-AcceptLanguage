# Kitura Accept-Language

*Warning: This project is still in an experimental state.* Indeed, it's not even really that useful in its current state, and is the product of a coder who's relatively new to Swift in general and Kitura specifically. I would not recommend using it in a production capacity unless you're willing to audit its behavior yourself. However, it may prove useful for those who also want to learn how to write Kitura middleware.

Kitura Accept-Language is [Kitura](https://github.com/IBM-Swift/Kitura) middleware that attempts to negotiate a match between human languages that your site has and languages that a user-agent requests via its [Accept-Language](https://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.4) header; or, in plain English, it helps your site provide content in a language a user understands.

## Usage

1. Add Kitura Accept-Language to your project using [Swift Package Manager](https://swift.org/package-manager/) as usual.

2. Initialize KAL. The signature for its init method is:

`init(acceptLangs: [String], sendContentLanguageHeader: Bool = true)`

`acceptLangs` is an array of language codes that your site will accept from users. For example, `["pt-br", "pt-pt", "pt", "es", "en"]`. The first language in the array will be the one selected if either the user-agent does not send an Accept-Language header, or if no match can be made between the user's requested languages and the ones your site supports.

If `sendContentLanguageHeader` is true, KAL will automatically add a Content-Language header to the response with the language code that it selected.

3. Attach the middleware to the routes you need it to work on.

4. In your route's callbacks, check the `negotiatedLanguage` property of your initialized KAL object for a structure with `langcode` and `matchQuality` properties. You'll also find a `negotiationStatus` enum telling you how the selected language was selected.

### Sample code

This code sample will probably explain everything better than the above.

```swift
import Kitura
import KituraAcceptLanguage

let router = Router()

let kal = AcceptLanguage(acceptLangs: ["en", "ja", "zh-hans", "es"])

router.all("/test", middleware: kal)
router.all("/test") { request, response, next in
    defer {
        next()
    }

    switch kal.negotiationStatus {
    case .Matched:
        response.send("Match between requested and supported languages made.\n")
    case .NoMatch:
        response.send("No match made; first supported language selected.\n")
    case .NoAcceptLanguageHeader:
        response.send("User-agent did not send Accept-Language header; first supported language selected.\n")
    case .NegotiationIncomplete:
        response.send("Language negotiation incomplete (you should never see this message).")
    }

    if let lang = kal.negotiatedLanguage {
        switch lang.langcode {
        case "en":
            response.send("Hello!\n")
        case "ja":
            response.send("こんにちは！\n")
        case "zh-hans":
            response.send("你好！\n")
        case "es":
            response.send("¡Hola!\n")
        default:
            response.send("This should never have happened.\n")
        }
    }
}

Kitura.addHTTPServer(onPort: 8080, with: router)
Kitura.run()
```

To test this best, you're going to want to be able to send different Accept-Language headers. Now you can theoretically tweak your standard web browser to do this, but since the process will differ based on what browser and/or operating system you're using, I'm not going to try to explain how. Instead, I'll show you how to use `curl` to test things. 

    > curl localhost:8080/test 
    User-agent did not send Accept-Language header; first supported language selected.
    Hello!
    
    >  curl localhost:8080/test -H "Accept-Language: zh-hans"
    Match between requested and supported languages made.
    你好！
    
    > curl localhost:8080/test -H "Accept-Language: no, zh-hant, ja, fr"
    Match between requested and supported languages made.
    こんにちは！
    
    > curl localhost:8080/test -H "Accept-Language: no, kr, pt-br"
    No match made; first supported language selected.
    Hello!

Of course, you can also use graphical request builder tools like Paw, Rested, etc.

## Rough todo list

- Moar comments, documentation, and code standards adherence!
- Also support language selection via a path prefix; eg, http://example.com/ja/about, http://example.com/zh-hans/about, etc. (Maybe that should be a separate package that integrates with this one…?)

import Foundation

// Workaround/hack for differing methods in macOS vs Linux.

#if os(Linux)
    extension TextCheckingResult {
        func rangeAt(_ idx: Int) -> Foundation.NSRange {
            return self.range(at: idx)
        }
    }
#endif


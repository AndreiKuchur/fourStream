import Foundation

struct StreamCredentials: Equatable, Sendable {
    var ingestURL: URL
    var streamKey: String
}

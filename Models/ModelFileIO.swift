import Foundation

/// Foundation can autorelease each returned NSData until the surrounding task
/// finishes. Drain temporary read/write/hash objects per chunk, including when
/// this is called from a Swift actor or a URLSession delegate operation.
public enum ModelFileIO {
    public static func forEachChunk(in input: FileHandle, maximumBytes: Int64 = .max,
                                    _ consume: (Data) throws -> Void) throws {
        guard maximumBytes >= 0 else { throw CocoaError(.fileReadCorruptFile) }
        var remaining = maximumBytes
        while remaining > 0 {
            try Task.checkCancellation()
            let read = try autoreleasepool { () throws -> Bool in
                guard let data = try input.read(upToCount: Int(min(65_536, remaining))), !data.isEmpty else { return false }
                try consume(data)
                remaining -= Int64(data.count)
                return true
            }
            if !read { break }
        }
    }
}

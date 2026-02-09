import Foundation
import Compression

/// Compression types supported by CDF
enum CDFCompressionType: Int32 {
    case none = 0
    case rle = 1       // Run-Length Encoding
    case huffman = 2   // Huffman
    case ahuffman = 3  // Adaptive Huffman
    case gzip = 5      // GZIP
}

/// Handles decompression of CDF data blocks
enum CDFCompression {

    /// Decompress GZIP-compressed data
    static func decompressGZIP(_ data: Data) throws -> Data {
        // GZIP data starts with magic bytes 0x1f 0x8b
        guard data.count >= 10,
              data[data.startIndex] == 0x1f,
              data[data.startIndex + 1] == 0x8b else {
            throw CDFError.decompressionFailed("Invalid GZIP header")
        }

        // Parse GZIP header to find where compressed data starts
        var headerSize = 10 // Minimum GZIP header size

        let flags = data[data.startIndex + 3]

        // Check for extra field
        if flags & 0x04 != 0 && data.count > headerSize + 2 {
            let extraLen = Int(data[data.startIndex + 10]) | (Int(data[data.startIndex + 11]) << 8)
            headerSize += 2 + extraLen
        }

        // Check for original filename
        if flags & 0x08 != 0 {
            var i = headerSize
            while i < data.count && data[data.startIndex + i] != 0 {
                i += 1
            }
            headerSize = i + 1
        }

        // Check for comment
        if flags & 0x10 != 0 {
            var i = headerSize
            while i < data.count && data[data.startIndex + i] != 0 {
                i += 1
            }
            headerSize = i + 1
        }

        // Check for header CRC
        if flags & 0x02 != 0 {
            headerSize += 2
        }

        // Remove header and 8-byte trailer (CRC32 + original size)
        let trailerSize = 8
        guard headerSize + trailerSize < data.count else {
            throw CDFError.decompressionFailed("GZIP data too short")
        }

        let compressedData = data[(data.startIndex + headerSize)..<(data.endIndex - trailerSize)]

        // Use Compression framework with raw deflate (ZLIB without header)
        return try decompressDeflate(Data(compressedData))
    }

    /// Decompress raw deflate data using Compression framework
    private static func decompressDeflate(_ data: Data) throws -> Data {
        // Allocate destination buffer - start with reasonable size
        var destinationBuffer = [UInt8](repeating: 0, count: data.count * 20)

        let decompressedSize = data.withUnsafeBytes { sourcePtr -> Int in
            guard let sourceBase = sourcePtr.baseAddress else { return 0 }
            return compression_decode_buffer(
                &destinationBuffer,
                destinationBuffer.count,
                sourceBase.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else {
            throw CDFError.decompressionFailed("Decompression failed - possibly corrupt data")
        }

        return Data(destinationBuffer.prefix(decompressedSize))
    }

    /// Decompress RLE-compressed data
    static func decompressRLE(_ data: Data, expectedSize: Int) throws -> Data {
        var result = Data(capacity: expectedSize)
        var index = data.startIndex

        while index < data.endIndex && result.count < expectedSize {
            let byte = data[index]
            index += 1

            if byte == 0x00 {
                // Run of zeros
                guard index < data.endIndex else {
                    throw CDFError.decompressionFailed("Unexpected end of RLE data")
                }
                let count = Int(data[index])
                index += 1
                result.append(contentsOf: [UInt8](repeating: 0, count: count))
            } else {
                // Literal byte
                result.append(byte)
            }
        }

        return result
    }
}

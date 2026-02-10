import Foundation

/// Errors that can occur when working with extended attributes
enum ExtendedAttributeError: Error, LocalizedError {
    case readFailed(String)
    case writeFailed(String)
    case removeFailed(String)

    var errorDescription: String? {
        switch self {
        case .readFailed(let name):
            return "Failed to read extended attribute: \(name)"
        case .writeFailed(let name):
            return "Failed to write extended attribute: \(name)"
        case .removeFailed(let name):
            return "Failed to remove extended attribute: \(name)"
        }
    }
}

extension URL {

    /// The extended attribute name used for CDF Viewer metadata
    static let cdfViewerMetadataAttributeName = "com.iotatech.cdfviewer.metadata"

    /// Read an extended attribute from the file
    /// - Parameter name: The attribute name
    /// - Returns: The attribute data, or nil if not present
    func extendedAttribute(forName name: String) -> Data? {
        let path = self.path

        // First, get the size of the attribute
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size > 0 else {
            return nil
        }

        // Allocate buffer and read the attribute
        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { buffer in
            getxattr(path, name, buffer.baseAddress, size, 0, 0)
        }

        guard result == size else {
            return nil
        }

        return data
    }

    /// Set an extended attribute on the file
    /// - Parameters:
    ///   - data: The attribute data
    ///   - name: The attribute name
    func setExtendedAttribute(_ data: Data, forName name: String) throws {
        let path = self.path

        let result = data.withUnsafeBytes { buffer in
            setxattr(path, name, buffer.baseAddress, buffer.count, 0, 0)
        }

        guard result == 0 else {
            throw ExtendedAttributeError.writeFailed(name)
        }
    }

    /// Remove an extended attribute from the file
    /// - Parameter name: The attribute name
    func removeExtendedAttribute(forName name: String) throws {
        let path = self.path
        let result = removexattr(path, name, 0)

        // ENOATTR (93) means attribute doesn't exist - that's OK
        guard result == 0 || errno == 93 else {
            throw ExtendedAttributeError.removeFailed(name)
        }
    }

    /// List all extended attributes on the file
    /// - Returns: Array of attribute names
    func listExtendedAttributes() -> [String] {
        let path = self.path

        // Get size needed for attribute list
        let size = listxattr(path, nil, 0, 0)
        guard size > 0 else {
            return []
        }

        // Read attribute names
        var buffer = [CChar](repeating: 0, count: size)
        let result = listxattr(path, &buffer, size, 0)
        guard result > 0 else {
            return []
        }

        // Parse null-separated names
        var names: [String] = []
        var current = ""
        for char in buffer {
            if char == 0 {
                if !current.isEmpty {
                    names.append(current)
                    current = ""
                }
            } else {
                current.append(Character(UnicodeScalar(UInt8(bitPattern: char))))
            }
        }

        return names
    }
}

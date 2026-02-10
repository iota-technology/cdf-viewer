import Foundation

/// Main CDF file reader with lazy loading support
final class CDFReader {
    private let reader: CDFBinaryReader
    private let url: URL

    // Parsed metadata
    private(set) var magic: CDFMagic?
    private(set) var cdr: CDFDescriptorRecord?
    private(set) var gdr: GlobalDescriptorRecord?
    private(set) var variables: [CDFVariable] = []
    private(set) var attributes: [CDFAttribute] = []
    private(set) var warnings: [CDFWarning] = []

    // Data endianness (from CDR encoding) - used for reading actual data values
    private var dataIsLittleEndian: Bool = true

    // Cache for decompressed data
    private var dataCache: [String: Data] = [:]
    private let cacheQueue = DispatchQueue(label: "com.cdfviewer.cache")

    init(url: URL) throws {
        self.url = url
        self.reader = try CDFBinaryReader(url: url)
    }

    /// Parse the CDF file headers and metadata
    func parse() throws {
        // CDF record structures are ALWAYS big-endian
        // Only data values use the file's encoding (from CDR)
        reader.setEndianness(false)  // Big-endian for record headers

        // Read magic number and validate
        guard let magic = CDFMagic(reader: reader) else {
            throw CDFError.invalidMagicNumber
        }
        self.magic = magic

        // Check major version (3 for CDF3.x files)
        guard magic.majorVersion == 3 else {
            throw CDFError.unsupportedVersion(magic.majorVersion, Int(magic.formatVersion))
        }

        // Read CDR (reader is already at byte 8 after magic)
        guard let cdr = CDFDescriptorRecord(reader: reader) else {
            throw CDFError.corruptedData("Failed to read CDF Descriptor Record")
        }
        self.cdr = cdr

        // Store the data encoding for reading actual data values later
        // Record structures stay big-endian, but data values use file's encoding
        dataIsLittleEndian = cdr.encoding.isLittleEndian

        // Read GDR
        reader.seek(to: cdr.gdrOffset)
        guard let gdr = GlobalDescriptorRecord(reader: reader) else {
            throw CDFError.corruptedData("Failed to read Global Descriptor Record")
        }
        self.gdr = gdr

        // Parse attributes
        try parseAttributes()

        // Parse zVariables
        if gdr.zVDRhead > 0 {
            try parseZVariables()
        }

        // Parse rVariables (if any)
        if gdr.rVDRhead > 0 {
            try parseRVariables()
        }
    }

    // MARK: - Attribute Parsing

    private func parseAttributes() throws {
        guard let gdr = gdr, gdr.aDRhead > 0 else { return }

        var offset = gdr.aDRhead
        while offset > 0 {
            reader.seek(to: offset)
            guard let adr = AttributeDescriptorRecord(reader: reader) else {
                warnings.append(CDFWarning(
                    message: "Failed to parse attribute at offset \(offset)",
                    location: "Attribute parsing",
                    severity: .warning
                ))
                break
            }

            var entries: [CDFAttributeEntry] = []

            // Parse global entries
            if adr.agrEDRhead > 0 {
                var entryOffset = adr.agrEDRhead
                while entryOffset > 0 {
                    reader.seek(to: entryOffset)
                    guard let entry = AttributeEntryRecord(reader: reader) else { break }
                    entries.append(CDFAttributeEntry(
                        entryNum: Int(entry.num),
                        dataType: entry.dataType,
                        value: entry.stringValue() ?? "<binary data>"
                    ))
                    entryOffset = entry.aedrNext
                }
            }

            // Parse variable entries
            if adr.azEDRhead > 0 {
                var entryOffset = adr.azEDRhead
                while entryOffset > 0 {
                    reader.seek(to: entryOffset)
                    guard let entry = AttributeEntryRecord(reader: reader) else { break }
                    entries.append(CDFAttributeEntry(
                        entryNum: Int(entry.num),
                        dataType: entry.dataType,
                        value: entry.stringValue() ?? "<binary data>"
                    ))
                    entryOffset = entry.aedrNext
                }
            }

            attributes.append(CDFAttribute(
                name: adr.name,
                isGlobal: adr.isGlobal,
                entries: entries
            ))

            offset = adr.adrNext
        }
    }

    // MARK: - Variable Parsing

    private func parseZVariables() throws {
        guard let gdr = gdr, gdr.zVDRhead > 0 else { return }

        var offset = gdr.zVDRhead
        while offset > 0 {
            reader.seek(to: offset)
            guard let vdr = VariableDescriptorRecord(reader: reader) else {
                warnings.append(CDFWarning(
                    message: "Failed to parse zVariable at offset \(offset)",
                    location: "Variable parsing",
                    severity: .warning
                ))
                break
            }

            // Get variable attributes
            let varAttributes = getAttributesForVariable(num: Int(vdr.num))

            let variable = CDFVariable(
                name: vdr.name,
                dataType: vdr.dataType,
                numElements: Int(vdr.numElems),
                dimensions: vdr.zDimSizes.map { Int($0) },
                dimVarys: vdr.dimVarys,
                maxRecord: Int(vdr.maxRec),
                isZVariable: true,
                vxrOffset: vdr.vxrHead,
                cprOffset: vdr.cprOrSprOffset,
                attributes: varAttributes
            )
            variables.append(variable)

            offset = vdr.vdrNext
        }
    }

    private func parseRVariables() throws {
        guard let gdr = gdr, gdr.rVDRhead > 0 else { return }

        var offset = gdr.rVDRhead
        while offset > 0 {
            reader.seek(to: offset)
            guard let vdr = VariableDescriptorRecord(reader: reader) else {
                warnings.append(CDFWarning(
                    message: "Failed to parse rVariable at offset \(offset)",
                    location: "Variable parsing",
                    severity: .warning
                ))
                break
            }

            let variable = CDFVariable(
                name: vdr.name,
                dataType: vdr.dataType,
                numElements: Int(vdr.numElems),
                dimensions: gdr.rDimSizes.map { Int($0) },
                dimVarys: vdr.dimVarys,
                maxRecord: Int(vdr.maxRec),
                isZVariable: false,
                vxrOffset: vdr.vxrHead,
                cprOffset: vdr.cprOrSprOffset,
                attributes: [:]
            )
            variables.append(variable)

            offset = vdr.vdrNext
        }
    }

    private func getAttributesForVariable(num: Int) -> [String: String] {
        var result: [String: String] = [:]
        for attr in attributes where !attr.isGlobal {
            for entry in attr.entries where entry.entryNum == num {
                result[attr.name] = entry.value
            }
        }
        return result
    }

    // MARK: - Data Reading

    /// Read all data for a variable
    func readVariableData(_ variable: CDFVariable) throws -> [CDFValue] {
        guard variable.vxrOffset > 0 else {
            return []
        }

        // Check cache
        if let cached = cacheQueue.sync(execute: { dataCache[variable.name] }) {
            return try decodeData(cached, variable: variable)
        }

        // Read VXR chain
        var allData = Data()
        var vxrOffset = variable.vxrOffset

        while vxrOffset > 0 {
            reader.seek(to: vxrOffset)
            guard let vxr = VariableIndexRecord(reader: reader) else {
                throw CDFError.dataReadFailed(variable: variable.name, reason: "Invalid VXR")
            }

            // Read data from each entry
            for entry in vxr.entries {
                reader.seek(to: entry.offset)

                // Peek at record type
                guard let recordSize = reader.readInt64(),
                      let recordTypeRaw = reader.readInt32() else {
                    throw CDFError.dataReadFailed(variable: variable.name, reason: "Cannot read record header")
                }

                reader.seek(to: entry.offset)

                if recordTypeRaw == CDFRecordType.vvr.rawValue {
                    // Uncompressed VVR
                    guard let vvr = VariableValuesRecord(reader: reader) else {
                        throw CDFError.dataReadFailed(variable: variable.name, reason: "Invalid VVR")
                    }
                    guard let data = reader.readBytes(vvr.dataSize) else {
                        throw CDFError.dataReadFailed(variable: variable.name, reason: "Cannot read VVR data")
                    }
                    allData.append(data)
                } else if recordTypeRaw == CDFRecordType.cvvr.rawValue {
                    // Compressed CVVR
                    guard let cvvr = CompressedVariableValuesRecord(reader: reader) else {
                        throw CDFError.dataReadFailed(variable: variable.name, reason: "Invalid CVVR")
                    }
                    guard let compressedData = reader.readBytes(Int(cvvr.compressedSize)) else {
                        throw CDFError.dataReadFailed(variable: variable.name, reason: "Cannot read compressed data")
                    }
                    let decompressed = try CDFCompression.decompressGZIP(compressedData)
                    allData.append(decompressed)
                } else {
                    warnings.append(CDFWarning(
                        message: "Unknown record type \(recordTypeRaw) for variable \(variable.name)",
                        location: "Data reading",
                        severity: .warning
                    ))
                }
            }

            vxrOffset = vxr.vxrNext
        }

        // Cache the data
        cacheQueue.sync { dataCache[variable.name] = allData }

        return try decodeData(allData, variable: variable)
    }

    /// Read a range of records for lazy loading
    func readVariableDataRange(_ variable: CDFVariable, startRecord: Int, count: Int) throws -> [CDFValue] {
        // For now, read all and slice - optimize later for very large files
        let allData = try readVariableData(variable)

        let recordSize = variable.totalElements
        let startIndex = startRecord * recordSize
        let endIndex = min(startIndex + count * recordSize, allData.count)

        guard startIndex < allData.count else { return [] }

        return Array(allData[startIndex..<endIndex])
    }

    /// Read raw doubles for a variable (optimized path for numeric data)
    func readVariableDoubles(_ variable: CDFVariable) throws -> [Double] {
        let values = try readVariableData(variable)
        return values.compactMap { $0.doubleValue }
    }

    /// Read raw Int64s for a variable (optimized for timestamps)
    func readVariableInt64s(_ variable: CDFVariable) throws -> [Int64] {
        let values = try readVariableData(variable)
        return values.compactMap { value in
            switch value {
            case .int64(let v): return v
            case .timeTT2000(let v): return v
            default: return nil
            }
        }
    }

    // MARK: - Data Decoding

    private func decodeData(_ data: Data, variable: CDFVariable) throws -> [CDFValue] {
        let dataReader = CDFBinaryReader(data: data)
        dataReader.setEndianness(dataIsLittleEndian)  // Use file's data encoding

        var values: [CDFValue] = []
        let totalElements = calculateTotalElements(variable)

        // For string types, handle differently
        if variable.dataType == .char || variable.dataType == .uchar {
            // Read as string chunks
            let stringLength = variable.numElements
            while !dataReader.isAtEnd {
                if let str = dataReader.readString(length: stringLength) {
                    values.append(.string(str))
                } else {
                    break
                }
            }
        } else {
            // Read as individual values
            while !dataReader.isAtEnd {
                if let value = dataReader.readCDFValue(type: variable.dataType) {
                    values.append(value)
                } else {
                    break
                }
            }
        }

        return values
    }

    private func calculateTotalElements(_ variable: CDFVariable) -> Int {
        if variable.dimensions.isEmpty {
            return (variable.maxRecord + 1) * variable.numElements
        }
        let dimProduct = variable.dimensions.reduce(1, *)
        return (variable.maxRecord + 1) * dimProduct
    }

    // MARK: - Convenience

    /// Find a variable by name
    func variable(named name: String) -> CDFVariable? {
        return variables.first { $0.name.lowercased() == name.lowercased() }
    }

    /// Get all timestamp variables
    func timestampVariables() -> [CDFVariable] {
        return variables.filter { $0.name.lowercased().contains("timestamp") || $0.dataType.isTimeType }
    }

    /// Get all ECEF variables
    func ecefVariables() -> [CDFVariable] {
        return variables.filter { $0.name.lowercased().contains("ecef") }
    }

    // MARK: - File Info

    func fileInfo(displayName: String? = nil) -> CDFFileInfo {
        CDFFileInfo(
            url: url,
            version: cdr.map { "\($0.version).\($0.release)" } ?? "Unknown",
            encoding: cdr?.encoding.displayName ?? "Unknown",
            majority: gdr.map { $0.rNumDims > 0 ? "Row" : "N/A" } ?? "Unknown",
            numVariables: variables.count,
            numAttributes: attributes.count,
            copyright: cdr?.copyright ?? "",
            displayName: displayName
        )
    }

    /// Clear cached data to free memory
    func clearCache() {
        cacheQueue.sync { dataCache.removeAll() }
    }
}

// MARK: - Supporting Types

struct CDFFileInfo {
    let url: URL
    let version: String
    let encoding: String
    let majority: String
    let numVariables: Int
    let numAttributes: Int
    let copyright: String
    let fileName: String

    init(url: URL, version: String, encoding: String, majority: String,
         numVariables: Int, numAttributes: Int, copyright: String,
         displayName: String? = nil) {
        self.url = url
        self.version = version
        self.encoding = encoding
        self.majority = majority
        self.numVariables = numVariables
        self.numAttributes = numAttributes
        self.copyright = copyright
        self.fileName = displayName ?? url.lastPathComponent
    }

    var fileSize: Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

struct CDFAttribute {
    let name: String
    let isGlobal: Bool
    let entries: [CDFAttributeEntry]
}

struct CDFAttributeEntry {
    let entryNum: Int
    let dataType: CDFDataType
    let value: String
}

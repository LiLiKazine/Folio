import UniformTypeIdentifiers

extension UTType {
    /// A `.cbz`: a zip under another name. The system declares no type for it, so the
    /// app declares one as an imported type in `Config/Folio-Types.plist`; without that
    /// declaration the file picker shows a `.cbz` greyed out.
    static let cbz = UTType(importedAs: "io.lilikaine.github.folio.cbz-archive", conformingTo: .zip)
}

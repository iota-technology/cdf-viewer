import Foundation

/// Represents the selection in the "Independent Variable" section of the sidebar.
/// This can be either a time variable (for time-series data) or the "Constants" pseudo-option
/// (for time-independent constant data).
enum IndependentVariableSelection: Equatable, Hashable {
    /// A time variable selected as the independent variable
    case timeVariable(CDFVariable)

    /// The "Constants" pseudo-option for viewing time-independent data
    case constants

    /// Whether this selection is the Constants pseudo-option
    var isConstants: Bool {
        if case .constants = self { return true }
        return false
    }

    /// The time variable if this is a time variable selection, nil otherwise
    var timeVariable: CDFVariable? {
        if case .timeVariable(let v) = self { return v }
        return nil
    }
}

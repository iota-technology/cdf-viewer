import SwiftUI

// MARK: - Error View

/// Displays errors encountered when loading CDF files
struct ErrorView: View {
    let error: Error

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Error Loading CDF File")
                .font(.title2)
                .fontWeight(.semibold)

            if let cdfError = error as? CDFError {
                Text(cdfError.localizedDescription)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let recovery = cdfError.recoverySuggestion {
                    Text(recovery)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            } else {
                Text(error.localizedDescription)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

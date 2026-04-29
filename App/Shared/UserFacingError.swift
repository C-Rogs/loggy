import Foundation

/// Maps implementation errors to short, actionable copy for alerts (detail still logged separately when needed).
enum UserFacingError {
    static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let d = localized.errorDescription, !d.isEmpty {
            return d
        }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return "Loggy doesn’t have permission to access that file. Try another location or check Files permissions."
            case NSFileReadCorruptFileError:
                return "That file doesn’t look readable. Try exporting again from Hevy."
            case NSFileNoSuchFileError:
                return "The file couldn’t be found. It may have moved—pick it again."
            case NSFileWriteOutOfSpaceError, NSFileWriteVolumeReadOnlyError:
                return "Not enough free space on this device to finish. Free storage and try again."
            default:
                break
            }
        }
        if ns.domain == URLError.errorDomain {
            return "The file couldn’t be opened. Try again or pick a different copy."
        }
        return "Something went wrong. Try again, use a smaller export, or restart Loggy if it keeps happening."
    }
}

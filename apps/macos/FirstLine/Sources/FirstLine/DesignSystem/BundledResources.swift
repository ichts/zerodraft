/**
 * [INPUT]: SwiftPM Bundle.module or the packaged app's Contents/Resources bundle
 * [OUTPUT]: One resource-bundle lookup for bundled fonts and brand artwork.
 * [POS]: Design-system resource boundary.
 * [PROTOCOL]: Check nearest AGENTS.md when this contract changes.
 */

import Foundation

enum BundledResources {
    static var bundle: Bundle {
        if let resources = Bundle.main.resourceURL,
           let packaged = Bundle(url: resources.appendingPathComponent("WriteItDown_WriteItDown.bundle")) {
            return packaged
        }
        return Bundle.module
    }
}

// The tests run on the Mac; Linux builds this target empty, without the view-test packages.
#if os(macOS)
import ViewInspector
@testable import GreetingsUI

extension Inspection: InspectionEmissary { }
#endif

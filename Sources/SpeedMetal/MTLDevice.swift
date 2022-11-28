import MetalKit

public extension MTLDevice {
    func makeLibrary(fromResourcesWithSuffixes suffixes: [String]) -> [MTLLibrary]? {
        var mtlLibrary: [MTLLibrary] = []
        
        for resourceSuffix in suffixes {
            // resource file suffixes must be 3 characters in SP4
            guard
                resourceSuffix.count == 3
            else { continue }
            
            for resourceFile in  Bundle.main.paths(forResourcesOfType: resourceSuffix, inDirectory: nil) {
                do {
                    let resourceContent = try String(contentsOfFile: resourceFile)
                    mtlLibrary.append(try makeLibrary(source: resourceContent, options: nil))
                } catch { continue }
            }
        }
        
        return mtlLibrary
    }
}

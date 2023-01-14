# SpeedMetal

Das Repository enthält die Sourcen der App zum Developer's Corner Artikel _Speed Metal_ im Apple-Magazin [Mac & i Heft X/2023, S. X](). Die App basiert auf der Codebase [Accelerating ray tracing using Metal](https://developer.apple.com/documentation/metal/metal_sample_code_library/accelerating_ray_tracing_using_metal), die Apple für die WWDC 2022 um einige Features des neuen [Metal 3](https://developer.apple.com/metal/) erweitert hat. Das Original ist in Objective-C für UIKit geschrieben, die App für den Artikel ist nach Swift portiert und für SwiftUI.

Nach dem Start rendert die App das erste Frame einer Szene mit neun Cornell Boxen. Am unteren Bildrand gibt es einige Controls: die ersten drei Buttons (von links) rendern das nächste Frame, beziehungsweise die nächsten zehn und die nächsten hundert Frames. Es folgen drei Buttons für Szenen mit einer, vier und neun Cornell Boxen. Der Button ganz rechts aktiviert den neuen Spatial Upscaler, der das Renderergebnis mit jedem Tap um den Faktor zwei vergrößert. Bei einem Wert von acht ist Schluss, und der Zyklus beginnt mit dem nächsten Tap von vorne.

Am oberen Bildrand aktualisiert die App die Laufzeit der Kommandos im Command Buffer, die SpeedMetal für jedes Frame ausführt.

SpeedMetal erfordert iOS/ iPadOS 16 und einen M1 Prozessor. Die Entwicklung der App erfolgte mit Swift Playgrounds 4 (SP4) auf einem iPad Pro 2022.

### Und so geht's:

#### TestFlight
- [SpeedMetal auf TestFlight]() für iPhone und iPad.

#### Swift Playgrounds 4
1. SP4 installieren und neue App öffnen
2. Vordefinierte Swift-Dateien löschen
3. Swift-Dateien aus Repository in App übertragen (copy&paste)
4. App in SP4 ausführen. Fertig.

### Links
- [Metal Documentation](https://developer.apple.com/documentation/metal)
- [Metal 3 Overview](https://developer.apple.com/metal/)
- Metal 3 on WWDC 2022 (ausgewählte Videos zum Mac & i Artikel)
  - [Discover Metal 3](https://developer.apple.com/videos/play/wwdc2022/10066/)
  - [Maximize your Metal ray tracing performance](https://developer.apple.com/videos/play/wwdc2022/10105/)
  - [Target and optimize GPU binaries with Metal 3](https://developer.apple.com/videos/play/wwdc2022/10102/)
  - [Boost performance with MetalFX Upscaling](https://developer.apple.com/videos/play/wwdc2022/10103/)
  - [Load resources faster with Metal 3](https://developer.apple.com/videos/play/wwdc2022/10104/)

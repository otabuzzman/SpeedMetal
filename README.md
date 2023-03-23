# SpeedMetal

Das Repository enthält die Sourcen der App zum Developer's Corner Artikel _Speed Metal_ im Apple-Magazin [Mac & i Heft 2/2023, S. 144](https://www.heise.de/select/mac-and-i/2023/2/). Die App basiert auf der Codebase [Accelerating ray tracing using Metal](https://developer.apple.com/documentation/metal/metal_sample_code_library/accelerating_ray_tracing_using_metal), die Apple für die WWDC 2022 um einige Features des neuen [Metal 3](https://developer.apple.com/metal/) erweitert hat. Das Original ist in Objective-C für UIKit geschrieben, die App für den Artikel ist nach Swift portiert und für SwiftUI.

Nach dem Start rendert die App einige Frames einer Szene mit neun Cornell Boxen. Am unteren Bildrand gibt es einige Controls: die ersten drei Buttons (von links) rendern die nächsten 5, 45 beziehungsweise die nächsten 90 Frames. Es folgen drei Buttons für Szenen mit einer, vier und neun Cornell Boxen. Der zweite Button von rechts aktiviert gegebenenfalls den Upscaler, der das Renderergebnis mit jedem Tap um den Faktor zwei vergrößert. Bei einem Wert von acht beginnt der Zyklus mit dem nächsten Tap von vorne. Der letzte Button ganz rechts öffnet die Files App zur Auswahl eines Folders, in dem SpeedMetal die kompilierten Shader und den Raytracer in der Datei `speedmetal.metallib` speichert. Die Datei lässt sich anschließend mittels [Offline Compilation](https://developer.apple.com/videos/play/wwdc2022/10102/) aufbereiten und zur Laufzeit laden, was SpeedMetal allerdings nicht unterstützt.

Im oberen Bildbereich aktualisiert die App die Laufzeiten der Kommandos im Command Buffer, den SpeedMetal für jedes Frame ausführt.

SpeedMetal erfordert iOS/ iPadOS 16 und mindestens einen A13 Prozessor, der Upscaler einen M1. Die Entwicklung der App erfolgte mit Swift Playgrounds 4 (SP4).

### Installation aus TestFlight (iPhone und iPad)
- [SpeedMetal auf TestFlight](https://testflight.apple.com/join/dgoPUBe9)

### Installation mit Swift Playgrounds 4 (iPad)
1. Neue App in SP4 erzeugen und öffnen
2. Vordefinierte Swift-Dateien löschen
3. Swift-Dateien aus Repository übertragen (copy&paste)
4. Grafiken aus Repository hinzufügen (Insert from...)
5. App in SP4 ausführen

### Links
- [Metal Documentation](https://developer.apple.com/documentation/metal)
- [Metal 3 Overview](https://developer.apple.com/metal/)

**Metal 3 on WWDC 2022 (ausgewählte Videos zum Artikel)**
- [Discover Metal 3](https://developer.apple.com/videos/play/wwdc2022/10066/)
- [Maximize your Metal ray tracing performance](https://developer.apple.com/videos/play/wwdc2022/10105/)
- [Target and optimize GPU binaries with Metal 3](https://developer.apple.com/videos/play/wwdc2022/10102/)
- [Boost performance with MetalFX Upscaling](https://developer.apple.com/videos/play/wwdc2022/10103/)
- [Load resources faster with Metal 3](https://developer.apple.com/videos/play/wwdc2022/10104/)

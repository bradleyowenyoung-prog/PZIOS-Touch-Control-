# Third-party components

pziOS uses the following projects. None of their binaries are committed here; build or fetch them as described in `docs/BUILDING.md`.

| Component | Used for | Source | Licence |
|---|---|---|---|
| OpenJDK 25 | The JVM (built for iOS) | https://github.com/openjdk/jdk (tag jdk-25.0.1+8) + `openjdk-25.0.1+8-pzios-source.patch.gz` attached to each release | GPLv2 + Classpath Exception (`licenses/OpenJDK-GPLv2-with-Classpath-Exception.txt`) |
| Baconium/iOS-JVM-s | Patches and scripts to build OpenJDK for iOS | https://github.com/Baconium/iOS-JVM-s | see repository |
| gl4es | OpenGL 2.x to OpenGL ES (unmodified, commit ec16bed) | https://github.com/ptitSeb/gl4es | MIT (`licenses/gl4es-MIT.txt`) |
| MetalANGLE | OpenGL ES on Metal | https://github.com/kakashidinho/metalangle | BSD-3-Clause (`licenses/MetalANGLE-BSD-3-Clause.txt`) |
| astc-encoder | ASTC texture compression | https://github.com/ARM-software/astc-encoder | Apache-2.0 (`licenses/astc-encoder-Apache-2.0.txt`) |
| StikJIT | Built-in JIT enabling (prebuilt `StikJIT.xcframework`, linked by the JIT helper) | https://github.com/StikDebug/StikJIT | MPL-2.0 (`licenses/StikJIT-MPL-2.0.txt`) |
 |

The release IPA also contains iOS-converted copies of the native libraries of Project Zomboid Build 42.21 (including FMOD by Firelight Technologies), which belong to their respective owners.

Project Zomboid is a trademark and work of The Indie Stone. 
pziOS is not affiliated with or endorsed by them and contains no game content.

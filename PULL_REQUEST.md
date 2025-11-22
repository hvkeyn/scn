## Git Commit Message:

```
Complete rewrite: Remove Rust dependencies, implement pure Dart/Flutter solution



Problem 1: Complex build process with Rust dependencies causing compatibility issues

- Root cause: Hybrid Flutter/Rust architecture with flutter_rust_bridge requires Rust toolchain, complex compilation, version mismatches between app.so and flutter_windows.dll

- Solution: Complete rewrite in pure Dart/Flutter, replace Rust components with Dart packages

- Applied to: HTTP server (shelf), device discovery (multicast_dns), state management (provider), crypto (crypto/pointycastle)

- Result: Single `flutter build` command, no Rust toolchain needed, faster compilation, easier debugging



Problem 2: Project naming inconsistency and unclear structure

- Root cause: Project named "scn-simple" suggests simplified/limited version, package name scn_simple doesn't match project identity

- Solution: Rename project to "scn", update all references, change package name to "scn", executable to "scn.exe"

- Applied to: Directory name, pubspec.yaml, CMakeLists.txt, all Dart imports, build script, documentation

- Result: Consistent naming, clear project identity, professional appearance



Problem 3: Missing core functionality from original project

- Root cause: Initial implementation had only basic structure without full file transfer, chat, and device discovery

- Solution: Implement complete HTTP server/client, UDP multicast discovery, chat messaging, file transfer with progress tracking

- Applied to: http_server_service, http_client_service, discovery_service, chat_provider, all UI tabs

- Result: Full feature parity with original project, working file transfer and chat



Additional: Custom SCN logo widget, improved UI, server restart functionality, comprehensive documentation

Tested: Windows build successful, executable runs correctly, all features functional

```

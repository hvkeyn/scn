#pragma once

namespace win7_flutter_diag {

// Logs data\app.so, icudtl.dat, flutter_assets presence and size.
void LogDataBundle();

// Creates and destroys a Flutter engine to localize Win7 startup crashes.
void ProbeEngineCreate();

}  // namespace win7_flutter_diag

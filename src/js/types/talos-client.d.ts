// Ambient declaration for @talos/client.
//
// The package ships a bundled dist/index.js without .d.ts. A proper fix
// would be emitting a bundled declaration (tsup --dts or similar) from
// the talos repo. Until then, treat imports as `any` so consumer tsc
// resolves the module without following the source graph (which pulls
// in the private @talos/schema workspace dep).
declare module "@talos/client";

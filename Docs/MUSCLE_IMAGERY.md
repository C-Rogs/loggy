# Muscle imagery (schematics and highlights)

Loggy does **not** download anatomy or highlight artwork at **runtime** from the open internet. That avoids unclear licensing, weak attribution in the UI, and App Review risk.

## Recommended workflow

1. **Pick a license-first asset**: CC0, public domain, purchased stock, or commissioned illustrations that permit redistribution in an iOS app.
2. **Vendor into the repo**: place vectors or bitmaps under `App/Resources/` or `Assets.xcassets`, ship only bundled files.
3. **Optional build-time fetch**: a script under `Scripts/` may download a **specific** Wikimedia or other URL **once** during development; commit the result and record the license (see `THIRD_PARTY_NOTICES.md`).
4. **App UI**: exercise movement continues to use `gif_url` from the database; muscle emphasis can combine **text** (primary/secondary slugs) with **tinted overlays** on a bundled outline when those assets exist.

## Statistics “body” screens

The weekly **Muscle distribution (Body)** view uses **data-driven lists** (week sections and muscle counts). Replacing that with a front/back heat diagram requires named regions in a vector asset or precomposed images—add when licensed artwork is available.

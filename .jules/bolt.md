## 2024-07-30 - Optimize Image Decoding Memory Footprint
**Learning:** Found an optimization where timeline video clip frames (using `Image.file()`) were decoded at full resolution. For apps with many frames or high-resolution clips, decoding at natural size causes OOM errors or heavy memory usage.
**Action:** Use `cacheWidth` or `cacheHeight` on `Image` constructors (like `Image.file` or `Image.network`) to decode images at the necessary resolution only, considering device pixel ratios (e.g. 120px cache for 40px widget size to accommodate 3x pixel ratio).

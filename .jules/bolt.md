## 2024-05-24 - Flutter Image Asset Memory Blowout

**Learning:** Unconstrained `Image.file` or `Image.asset` widgets will decode full-resolution image buffers into memory, even if displayed in a tiny box. For high-res video thumbnails on a timeline, this will quickly cause OOM crashes or massive memory bloat (e.g. an 8MB buffer for a 40x40 pixel thumbnail).

**Action:** Always add `cacheWidth` or `cacheHeight` constraints to Image constructors when displaying large image files at small target sizes to instruct the Flutter engine to downsample during decode.

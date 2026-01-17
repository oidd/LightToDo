# Image Inline Layout Fix Summary

## Achieved Goals
1.  **True Inline Layout**: Images now flow naturally with text, respecting the `inline` display property. This was achieved by:
    *   Injecting `this.isInline = () => true;` into the `ImageNode` constructor.
    *   Changing the node's DOM structure from `div` -> `span` to ensure valid HTML nesting inside paragraphs.
    *   Applying `display: inline` to the outer node and `display: inline-block` to the inner wrapper via CSS.

2.  **Visual Alignment**: Images are bottom-aligned with text (`vertical-align: bottom`), strictly adhering to user preference for aesthetic integration.

3.  **Resizer Functionality**:
    *   All 8 resize handles are correctly positioned **inside** the image boundaries (`inset: 0` logic + handle offsets).
    *   Resizer overlay no longer expands beyond the image dimensions.

4.  **Cursor Visibility**:
    *   Added `margin: 0 4px` to the image wrapper to ensure the cursor is always visible and not clipped when placed next to an image.
    *   Accepted the browser's default cursor height behavior for bottom-aligned inline-blocks as a necessary trade-off for correct alignment.

## Technical Details
*   **Files Modified**:
    *   `src/nodes/ImageNode.tsx`: Forced inline behavior.
    *   `src/nodes/ImageComponent.tsx`: Updated wrapper element to `span` and set inline styles.
    *   `src/ui/ImageResizer.tsx`: Updated handles to `span` and fixed positioning logic.
    *   `src/index.css`: Consolidated and prioritized CSS rules for `.editor-image`, `.image-wrapper`, and `.image-resizer`.

## Known Constraints
*   **Cursor Height**: The cursor height next to the image will match the line height (which includes the image). This is standard browser behavior for `vertical-align: bottom` on inline-block elements and is required to maintain the desired visual alignment. Using `font-size: 0` hacks proved unstable for layout properties.

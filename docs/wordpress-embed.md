# Embedding the map in WordPress

The Sprinkling Seeds app, with the form and the map, is a standalone page at `https://aaronsexton.github.io/`. WordPress shows it inside an `<iframe>`.

## Embed code

Add a **Custom HTML** block to the page or post and paste:

```html
<iframe
  id="sprinkling-seeds"
  src="https://aaronsexton.github.io/"
  title="Sprinkling Seeds: add your planting"
  allow="geolocation; fullscreen"
  loading="lazy"
  style="width: 100%; border: 0; height: 1400px;"
></iframe>
<script>
  addEventListener('message', function (e) {
    if (e.origin !== 'https://aaronsexton.github.io') return;
    if (!e.data || e.data.type !== 'sprinkling-seeds:height') return;
    document.getElementById('sprinkling-seeds').style.height = e.data.height + 'px';
  });
</script>
```

### What each part does

- **`allow="geolocation; fullscreen"`:** browsers block location access and fullscreen inside iframes unless the parent page allows them. Without `geolocation`, the "Use my location" button won't work, but visitors can still tap the map to place a pin. Without `fullscreen`, the maps' fullscreen buttons only fill the iframe, not the screen.
- **The `<script>`:** the app sends a message with its content height whenever that height changes, for example when a status message appears. This listener resizes the iframe to match, so there's no inner scrollbar. It ignores messages from any other origin.
- **`height: 1400px`:** a starting height used until the first message arrives, and the permanent height if the script can't run.
- **`title`:** read aloud by screen readers to describe the iframe.

## If WordPress removes the script

Depending on the site's setup, WordPress may strip `<script>` tags from post content. This happens for users without the `unfiltered_html` capability, on WordPress.com plans without plugin support, or with some security plugins. If the iframe stays at 1400px and doesn't resize:

1. Add the script site-wide with a code-snippets plugin, such as WPCode, set to load in the footer, or add it to the theme's footer. Keep only the iframe in the Custom HTML block.
2. Or skip auto-resizing: drop the script and pick a fixed height that fits the form and map on both phone and desktop. About `1500px` works on phones, where the form fields stack.

## Notes

- **No app changes are needed for embedding.** GitHub Pages doesn't send headers that block framing, and Cloudflare Turnstile works inside iframes.
- **CORS:** the Edge Function sees the iframe's origin (`https://aaronsexton.github.io`), not the WordPress site's, so its `ALLOWED_ORIGINS` doesn't need the WordPress domain.
- **Scrolling:** the maps use cooperative gestures. Scrolling over them scrolls the WordPress page, and zooming needs ctrl/cmd + scroll, or two fingers on touch screens. Each map's fullscreen button (bottom right) turns this off while it's open, so one finger pans the map.
- **iPhone:** Safari on iPhone can't make a page element fullscreen, so there the fullscreen buttons fill the iframe instead of the screen.
- **Custom domain:** if the app moves to a custom domain, update `src` and the `e.origin` check here, the function's `ALLOWED_ORIGINS`, and the Turnstile widget's hostnames.

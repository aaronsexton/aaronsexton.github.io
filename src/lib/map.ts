import { FullscreenControl, MapLibreMap, NavigationControl, setWorkerUrl, type MapOptions } from 'maplibre-gl';
import workerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?url';
import 'maplibre-gl/dist/maplibre-gl.css';
import { MAP_CENTER, MAP_STYLE, MAP_ZOOM } from './config';

// MapLibre finds its worker relative to its own file, which Vite moves when it
// bundles; point it at the worker explicitly so dev and production builds both work
setWorkerUrl(workerUrl);

// a map with the site's style, starting view, and zoom buttons
export function createMap(container: string | HTMLElement, options: Partial<MapOptions> = {}): MapLibreMap {
  const map = new MapLibreMap({
    container,
    style: MAP_STYLE,
    center: MAP_CENTER,
    zoom: MAP_ZOOM,
    cooperativeGestures: true, // scroll-zoom needs ctrl/cmd, so the embedding page still scrolls
    ...options,
  });
  map.addControl(new NavigationControl({ showCompass: false }), 'top-right');
  return map;
}

// A fullscreen button in the bottom-right. `frame` (class "map-frame") is what goes
// fullscreen: it becomes a translucent backdrop and its child a centered card, styled
// in global.css. Fullscreen turns off cooperative gestures, so one finger pans.
// Where real fullscreen is blocked (an iframe without allow="fullscreen", or iPhone
// Safari), the control falls back to filling the window with CSS.
export function addFullscreenControl(map: MapLibreMap, frame: HTMLElement): void {
  map.addControl(new FullscreenControl({ container: frame, pseudo: !document.fullscreenEnabled }), 'bottom-right');

  // clicking the backdrop around the card exits fullscreen
  frame.addEventListener('click', (e) => {
    if (e.target === frame) frame.querySelector<HTMLButtonElement>('.maplibregl-ctrl-shrink')?.click();
  });
}

import { MapLibreMap, NavigationControl, setWorkerUrl, type MapOptions } from 'maplibre-gl';
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

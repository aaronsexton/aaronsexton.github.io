// The form and the map communicate through events on `document`, so neither
// component imports the other.

import type { Feature, Point } from 'geojson';

export interface PlantingProperties {
  id: string;
  title: string;
  created_at: string;
}

export type PlantingFeature = Feature<Point, PlantingProperties>;

interface PlantingEvents {
  // a submission succeeded: the map shows the new point, the location picker clears
  'planting:added': PlantingFeature;
}

export function emit<K extends keyof PlantingEvents>(type: K, detail: PlantingEvents[K]): void {
  document.dispatchEvent(new CustomEvent(type, { detail }));
}

export function on<K extends keyof PlantingEvents>(
  type: K,
  handler: (detail: PlantingEvents[K]) => void,
): void {
  document.addEventListener(type, (e) => handler((e as CustomEvent<PlantingEvents[K]>).detail));
}

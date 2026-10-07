// Screenshots are optional at build time: any PNG dropped into src/assets/screenshots is picked
// up by name, and a shot without a file falls back to its sketch (or is left out).
const files = import.meta.glob<{ default: ImageMetadata }>('../assets/screenshots/*.png', { eager: true });

export function screenshot(name: string): ImageMetadata | undefined {
  return files[`../assets/screenshots/${name}.png`]?.default;
}

export const sketchFor: Record<string, 'app' | 'scene' | 'combat' | 'notes'> = {
  main: 'app',
  'scene-editor': 'scene',
  combat: 'combat',
  notes: 'notes',
};

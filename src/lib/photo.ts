import imageCompression from 'browser-image-compression';

const MAX_DIMENSION = 2000; // px, long edge
const MAX_SIZE_MB = 1;

// HEIF "ftyp" brands used by HEIC/HEIF photos (iPhone photos are usually heic or mif1)
const HEIF_BRANDS = new Set(['heic', 'heix', 'hevc', 'hevx', 'heim', 'heis', 'mif1', 'msf1']);

// Checks the file's bytes, since browsers often report an empty or generic type for HEIC files
async function isHeic(file: File): Promise<boolean> {
  if (/image\/hei[cf]/i.test(file.type) || /\.hei[cf]$/i.test(file.name)) return true;
  const header = new Uint8Array(await file.slice(0, 12).arrayBuffer());
  const text = String.fromCharCode(...header);
  return text.slice(4, 8) === 'ftyp' && HEIF_BRANDS.has(text.slice(8, 12));
}

function jpegName(name: string): string {
  return name.replace(/\.[^.]+$/, '') + '.jpg';
}

// Converts HEIC to JPEG and resizes/compresses every photo to a JPEG under ~1 MB,
// so uploads are small and display in every browser.
export async function preparePhoto(file: File): Promise<File> {
  let source: Blob = file;

  if (await isHeic(file)) {
    try {
      // heic-to bundles a ~3 MB decoder, so load it only when needed
      const { heicTo } = await import('heic-to');
      source = await heicTo({ blob: file, type: 'image/jpeg', quality: 0.9 });
    } catch (err) {
      // Safari can decode HEIC itself, so let the compressor try the original file
      console.warn('HEIC conversion failed; trying the browser’s own decoder', err);
    }
  }

  const compressed = await imageCompression(new File([source], jpegName(file.name), { type: source.type || file.type }), {
    maxWidthOrHeight: MAX_DIMENSION,
    maxSizeMB: MAX_SIZE_MB,
    fileType: 'image/jpeg',
    useWebWorker: true,
  });

  return new File([compressed], jpegName(file.name), { type: 'image/jpeg' });
}

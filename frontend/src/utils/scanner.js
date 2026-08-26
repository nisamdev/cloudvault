/**
 * The imaging half of the scanner: everything that turns a photograph of a
 * document into something that looks scanned.
 *
 * All of it runs in the browser, deliberately. The user drags the corners of
 * the crop and switches filters, and the only way that stays honest is for the
 * preview and the saved page to come out of the same code. The server receives
 * finished pages and never touches the pixels.
 */

/** What the editor offers, in the order it offers it. */
export const FILTERS = [
  { value: "document", label: "Document", hint: "Shadows removed, text lifted" },
  { value: "bw", label: "Black & white", hint: "Hard contrast, smallest file" },
  { value: "greyscale", label: "Greyscale", hint: "Plain grey, nothing else" },
  { value: "enhanced", label: "Colour boost", hint: "White paper, stronger colour" },
  { value: "original", label: "Original", hint: "The photo as taken" },
];

/** Long edge of a saved page. Anything more is invisible on paper. */
export const QUALITIES = [
  { value: 1200, label: "Small", hint: "Quickest, smallest file" },
  { value: 1800, label: "Standard", hint: "Reads well on screen and on paper" },
  { value: 2600, label: "High", hint: "For small print and fine detail" },
];

/** The whole image, as the starting crop. */
export const FULL_FRAME = [
  { x: 0, y: 0 },
  { x: 1, y: 0 },
  { x: 1, y: 1 },
  { x: 0, y: 1 },
];

/* -------------------------------------------------------------- loading */

/**
 * Loads a blob into an <img>.
 *
 * An element rather than createImageBitmap: browsers apply EXIF orientation to
 * an <img> by default and report naturalWidth/Height already rotated, so a
 * photo taken sideways arrives upright everywhere. createImageBitmap needs an
 * option for that which Safari has ignored for years, silently.
 */
export function loadImage(blob) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(blob);
    const image = new Image();

    image.onload = () => {
      URL.revokeObjectURL(url);
      resolve(image);
    };
    image.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("That image could not be opened."));
    };

    image.src = url;
  });
}

/**
 * Draws the image onto a canvas, applying a quarter-turn and capping the size.
 *
 * Everything downstream works on this canvas, so rotation stops being a special
 * case the moment the pixels are laid down.
 */
export function toCanvas(image, { rotation = 0, maxDimension = 1600 } = {}) {
  const turned = rotation === 90 || rotation === 270;
  const sourceWidth = image.naturalWidth ?? image.width;
  const sourceHeight = image.naturalHeight ?? image.height;

  const width = turned ? sourceHeight : sourceWidth;
  const height = turned ? sourceWidth : sourceHeight;
  const scale = Math.min(1, maxDimension / Math.max(width, height));

  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(width * scale));
  canvas.height = Math.max(1, Math.round(height * scale));

  const context = canvas.getContext("2d", { willReadFrequently: true });
  context.imageSmoothingQuality = "high";
  context.translate(canvas.width / 2, canvas.height / 2);
  context.rotate((rotation * Math.PI) / 180);
  context.drawImage(
    image,
    (-sourceWidth * scale) / 2,
    (-sourceHeight * scale) / 2,
    sourceWidth * scale,
    sourceHeight * scale,
  );

  return canvas;
}

function imageDataOf(canvas) {
  return canvas.getContext("2d", { willReadFrequently: true }).getImageData(0, 0, canvas.width, canvas.height);
}

/* ------------------------------------------------------------ detection */

/**
 * Guesses where the page is inside the photo.
 *
 * The page is the one large area of even tone in the frame, so a two-way split
 * of the brightness (Otsu's method) separates it from the surface underneath.
 * Its corners are then the extremes along each diagonal: the top-left corner is
 * whichever page pixel has the smallest x + y, and so on round.
 *
 * Taking the diagonal extremes rather than a bounding box is what makes the
 * guess follow a tilt. A page lying at an angle has four distinct diagonal
 * extremes — its actual corners — where a box would put four triangles of table
 * inside the crop for the document filters to turn black. A page lying square
 * has four extremes that land back on the box, which is also right.
 *
 * It gives up rather than guess badly, returning the whole frame when the split
 * finds one population instead of two (an evenly lit close-up) or when what it
 * found is too small to be the document. Dragging the corners is the real
 * control; this is only meant to save most people from having to.
 *
 * @returns {Array<{x: number, y: number}>} corners clockwise from the top left,
 *   as fractions of the image.
 */
export function detectPage(canvas) {
  const { grey, width, height } = greyPreview(canvas, 260);

  return detectPageIn(grey, width, height);
}

/**
 * The detection itself, over a plain greyscale buffer.
 *
 * Separated from the canvas so it can be exercised directly: this is geometry
 * and statistics, and neither needs a browser to be wrong in.
 */
export function detectPageIn(grey, width, height) {
  const wholeFrame = () => FULL_FRAME.map((corner) => ({ ...corner }));
  if (width < 24 || height < 24) return wholeFrame();

  const split = otsu(grey);
  if (split === null) return wholeFrame();

  // A dark document on a pale table is as ordinary as the other way round, so
  // which side of the split is "the page" is decided by what is in the middle
  // of the frame rather than assumed.
  //
  // Compared against the two sides' averages rather than against the threshold
  // itself. Otsu only has to return *a* value in the valley between them, and
  // when the two are far apart that value can sit right against one of them —
  // which would make a photo of a dark object on a pale table come out as
  // "everything is the page".
  const centre = centreBrightness(grey, width, height);
  const pageIsBright = Math.abs(centre - split.bright) < Math.abs(centre - split.dark);

  const xs = [];
  const ys = [];
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const value = grey[y * width + x];
      if (pageIsBright ? value <= split.threshold : value > split.threshold) continue;

      xs.push(x);
      ys.push(y);
    }
  }

  // Too little of the frame to be the document: the split found the text, or a
  // highlight, and cropping to it would throw the page away.
  if (xs.length < grey.length * MIN_PAGE_SHARE) return wholeFrame();

  const corner = (score) => {
    const order = Uint32Array.from(xs.keys()).sort((a, b) => score(a) - score(b));
    // A fraction in from the very extreme, so one stray bright speck on the
    // table cannot pull a corner out to meet it.
    const at = order[Math.floor(order.length * 0.002)];

    return { x: xs[at] / (width - 1), y: ys[at] / (height - 1) };
  };

  return [
    corner((i) => xs[i] + ys[i]),
    corner((i) => -(xs[i] - ys[i])),
    corner((i) => -(xs[i] + ys[i])),
    corner((i) => xs[i] - ys[i]),
  ];
}

/** Below this share of the frame, whatever was found is not the document. */
const MIN_PAGE_SHARE = 0.15;

/**
 * Otsu's split: the threshold leaving the two sides as tight as possible, with
 * the average of each side. Values up to and including the threshold are the
 * darker side.
 *
 * @returns {{threshold: number, dark: number, bright: number}|null} null when
 *   there is only one population to be found.
 */
function otsu(grey) {
  const histogram = new Uint32Array(256);
  for (let i = 0; i < grey.length; i += 1) {
    histogram[Math.min(255, Math.max(0, grey[i] | 0))] += 1;
  }

  const count = grey.length;
  if (count === 0) return null;

  let total = 0;
  for (let value = 0; value < 256; value += 1) total += value * histogram[value];

  let belowWeight = 0;
  let belowSum = 0;
  let best = 0;
  let bestVariance = 0;

  for (let value = 0; value < 256; value += 1) {
    belowWeight += histogram[value];
    if (belowWeight === 0) continue;

    const aboveWeight = count - belowWeight;
    if (aboveWeight === 0) break;

    belowSum += value * histogram[value];
    const difference = belowSum / belowWeight - (total - belowSum) / aboveWeight;
    const variance = belowWeight * aboveWeight * difference * difference;

    if (variance > bestVariance) {
      bestVariance = variance;
      best = value;
    }
  }

  // One population, not two: an evenly toned image has no page in it to find.
  if (bestVariance <= 0) return null;

  let darkWeight = 0;
  let darkSum = 0;
  for (let value = 0; value <= best; value += 1) {
    darkWeight += histogram[value];
    darkSum += value * histogram[value];
  }

  return {
    threshold: best,
    dark: darkSum / darkWeight,
    bright: (total - darkSum) / (count - darkWeight),
  };
}

/** Mean brightness of the middle of the frame, which is page if anything is. */
function centreBrightness(grey, width, height) {
  const fromX = Math.round(width * 0.35);
  const toX = Math.round(width * 0.65);
  const fromY = Math.round(height * 0.35);
  const toY = Math.round(height * 0.65);

  let sum = 0;
  let count = 0;
  for (let y = fromY; y < toY; y += 1) {
    for (let x = fromX; x < toX; x += 1) {
      sum += grey[y * width + x];
      count += 1;
    }
  }

  return count ? sum / count : 0;
}

/** A small greyscale copy — detection does not need the full resolution. */
function greyPreview(canvas, target) {
  const scale = Math.min(1, target / Math.max(canvas.width, canvas.height));
  const width = Math.max(1, Math.round(canvas.width * scale));
  const height = Math.max(1, Math.round(canvas.height * scale));

  const small = document.createElement("canvas");
  small.width = width;
  small.height = height;
  small.getContext("2d").drawImage(canvas, 0, 0, width, height);

  const { data } = small.getContext("2d").getImageData(0, 0, width, height);
  const grey = new Float32Array(width * height);
  for (let i = 0, p = 0; i < data.length; i += 4, p += 1) {
    grey[p] = 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];
  }

  return { grey, width, height };
}

/* ---------------------------------------------------------- perspective */

/**
 * Solves the 3x3 projective transform taking each `from` point to its `to`
 * partner, with h22 fixed at 1. Eight unknowns, four correspondences, two
 * equations each — an exact fit rather than a least-squares one.
 *
 * @returns {Float64Array} the nine coefficients, row-major.
 */
export function solveHomography(from, to) {
  const a = [];
  const b = [];

  for (let i = 0; i < 4; i += 1) {
    const { x, y } = from[i];
    const { x: u, y: v } = to[i];

    a.push([x, y, 1, 0, 0, 0, -x * u, -y * u]);
    b.push(u);
    a.push([0, 0, 0, x, y, 1, -x * v, -y * v]);
    b.push(v);
  }

  const h = gaussianSolve(a, b);
  if (!h) return null;

  return Float64Array.from([h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1]);
}

/** Gaussian elimination with partial pivoting. Null when the system is singular. */
function gaussianSolve(matrix, vector) {
  const n = vector.length;
  const rows = matrix.map((row, i) => [...row, vector[i]]);

  for (let column = 0; column < n; column += 1) {
    let pivot = column;
    for (let row = column + 1; row < n; row += 1) {
      if (Math.abs(rows[row][column]) > Math.abs(rows[pivot][column])) pivot = row;
    }
    if (Math.abs(rows[pivot][column]) < 1e-10) return null;

    [rows[column], rows[pivot]] = [rows[pivot], rows[column]];

    for (let row = 0; row < n; row += 1) {
      if (row === column) continue;

      const factor = rows[row][column] / rows[column][column];
      for (let k = column; k <= n; k += 1) rows[row][k] -= factor * rows[column][k];
    }
  }

  // Gauss-Jordan leaves one non-zero coefficient per row: the diagonal.
  return rows.map((row, i) => row[n] / row[i]);
}

/**
 * The size a crop should come out at: the longest opposing pair of edges, so a
 * quad tilted in perspective is straightened back to the shape the page really
 * is rather than to the shape it appears in the photo.
 */
export function croppedSize(corners, width, height, maxDimension) {
  const points = corners.map((corner) => ({ x: corner.x * width, y: corner.y * height }));
  const span = (a, b) => Math.hypot(points[a].x - points[b].x, points[a].y - points[b].y);

  let outWidth = Math.max(span(0, 1), span(3, 2));
  let outHeight = Math.max(span(0, 3), span(1, 2));

  const scale = Math.min(1, maxDimension / Math.max(outWidth, outHeight));
  outWidth = Math.max(1, Math.round(outWidth * scale));
  outHeight = Math.max(1, Math.round(outHeight * scale));

  return { width: outWidth, height: outHeight };
}

/**
 * Straightens the quadrilateral the corners describe into a rectangle.
 *
 * The transform is solved the other way round — output back to input — so every
 * destination pixel asks where it came from. Mapping forwards would leave holes
 * wherever the image is stretched.
 */
export function warp(canvas, corners, size) {
  const source = imageDataOf(canvas);
  const { width: sw, height: sh } = source;

  const target = [
    { x: 0, y: 0 },
    { x: size.width, y: 0 },
    { x: size.width, y: size.height },
    { x: 0, y: size.height },
  ];
  const quad = corners.map((corner) => ({ x: corner.x * sw, y: corner.y * sh }));

  const h = solveHomography(target, quad);
  // A degenerate quad (three corners in a line) has no transform; the honest
  // fallback is the uncropped image rather than a blank page.
  if (!h) return source;

  const output = new ImageData(size.width, size.height);
  const out = output.data;
  const src = source.data;

  for (let y = 0; y < size.height; y += 1) {
    for (let x = 0; x < size.width; x += 1) {
      const denominator = h[6] * x + h[7] * y + 1;
      const u = (h[0] * x + h[1] * y + h[2]) / denominator;
      const v = (h[3] * x + h[4] * y + h[5]) / denominator;

      const index = (y * size.width + x) * 4;

      if (u < 0 || v < 0 || u > sw - 1 || v > sh - 1) {
        // Outside the photo: white, so a crop dragged past the edge reads as
        // paper rather than as a black border.
        out[index] = 255;
        out[index + 1] = 255;
        out[index + 2] = 255;
        out[index + 3] = 255;
        continue;
      }

      const x0 = u | 0;
      const y0 = v | 0;
      const x1 = Math.min(x0 + 1, sw - 1);
      const y1 = Math.min(y0 + 1, sh - 1);
      const fx = u - x0;
      const fy = v - y0;

      const topLeft = (y0 * sw + x0) * 4;
      const topRight = (y0 * sw + x1) * 4;
      const bottomLeft = (y1 * sw + x0) * 4;
      const bottomRight = (y1 * sw + x1) * 4;

      for (let channel = 0; channel < 3; channel += 1) {
        const top = src[topLeft + channel] + (src[topRight + channel] - src[topLeft + channel]) * fx;
        const bottom =
          src[bottomLeft + channel] + (src[bottomRight + channel] - src[bottomLeft + channel]) * fx;
        out[index + channel] = top + (bottom - top) * fy;
      }
      out[index + 3] = 255;
    }
  }

  return output;
}

/* --------------------------------------------------------------- filters */

/**
 * Applies a look and the manual brightness/contrast on top of it, in place.
 *
 * @param {ImageData} image
 * @param {{filter: string, brightness: number, contrast: number}} options
 *   brightness and contrast are -100..100, 0 meaning untouched.
 */
export function applyFilter(image, { filter = "document", brightness = 0, contrast = 0 } = {}) {
  switch (filter) {
    case "greyscale":
      desaturate(image);
      break;
    case "document":
      removeShadows(image, { gain: 1.6 });
      break;
    case "bw":
      binarise(image);
      break;
    case "enhanced":
      whiteBalance(image);
      break;
    default:
      break;
  }

  if (brightness !== 0 || contrast !== 0) adjust(image, brightness, contrast);

  return image;
}

function luma(data, index) {
  return 0.299 * data[index] + 0.587 * data[index + 1] + 0.114 * data[index + 2];
}

function desaturate(image) {
  const { data } = image;
  for (let i = 0; i < data.length; i += 4) {
    const grey = luma(data, i);
    data[i] = grey;
    data[i + 1] = grey;
    data[i + 2] = grey;
  }
}

/** Brightness as a shift, contrast as a pivot around mid-grey. One LUT, three channels. */
function adjust(image, brightness, contrast) {
  const shift = brightness * 1.5;
  const amount = contrast * 1.5;
  const factor = (259 * (amount + 255)) / (255 * (259 - amount));

  const lut = new Uint8ClampedArray(256);
  for (let value = 0; value < 256; value += 1) {
    lut[value] = factor * (value + shift - 128) + 128;
  }

  const { data } = image;
  for (let i = 0; i < data.length; i += 4) {
    data[i] = lut[data[i]];
    data[i + 1] = lut[data[i + 1]];
    data[i + 2] = lut[data[i + 2]];
  }
}

/**
 * Divides the image by its own local brightness.
 *
 * This is what makes a photograph look scanned. The shadow of the hand holding
 * the phone, and the gradient across a page lit from one side, are both *low
 * frequency*: dividing each pixel by the average around it cancels them and
 * leaves the ink, because ink is small and the shadow is large. Text then gets
 * a gain so it comes back black rather than dark grey.
 */
function removeShadows(image, { gain = 1.6 } = {}) {
  const { data, width, height } = image;
  const grey = new Float32Array(width * height);
  for (let i = 0, p = 0; i < data.length; i += 4, p += 1) grey[p] = luma(data, i);

  const background = localMean(grey, width, height);

  for (let p = 0, i = 0; p < grey.length; p += 1, i += 4) {
    // Guarded: a genuinely black region would otherwise divide by nothing and
    // bloom to white.
    const normalised = (grey[p] / Math.max(background[p], 24)) * 235;
    const value = 255 - Math.min(255, (255 - Math.min(255, normalised)) * gain);

    data[i] = value;
    data[i + 1] = value;
    data[i + 2] = value;
  }
}

/** The same local mean, used as a threshold instead of a divisor (Bradley's method). */
function binarise(image, { bias = 0.9 } = {}) {
  const { data, width, height } = image;
  const grey = new Float32Array(width * height);
  for (let i = 0, p = 0; i < data.length; i += 4, p += 1) grey[p] = luma(data, i);

  const background = localMean(grey, width, height);

  for (let p = 0, i = 0; p < grey.length; p += 1, i += 4) {
    const value = grey[p] < background[p] * bias ? 0 : 255;
    data[i] = value;
    data[i + 1] = value;
    data[i + 2] = value;
  }
}

/**
 * Mean brightness of the box around each pixel, from a summed-area table — so
 * the window size costs nothing and a big radius is as cheap as a small one.
 */
function localMean(grey, width, height) {
  const integral = new Float64Array((width + 1) * (height + 1));

  for (let y = 0; y < height; y += 1) {
    let rowSum = 0;
    for (let x = 0; x < width; x += 1) {
      rowSum += grey[y * width + x];
      integral[(y + 1) * (width + 1) + (x + 1)] = integral[y * (width + 1) + (x + 1)] + rowSum;
    }
  }

  // Wide enough to span a word — narrower and the middle of a thick letter
  // reads as its own background and comes out white.
  const radius = Math.max(8, Math.round(Math.min(width, height) / 24));
  const means = new Float32Array(width * height);

  for (let y = 0; y < height; y += 1) {
    const top = Math.max(0, y - radius);
    const bottom = Math.min(height - 1, y + radius);

    for (let x = 0; x < width; x += 1) {
      const left = Math.max(0, x - radius);
      const right = Math.min(width - 1, x + radius);
      const count = (bottom - top + 1) * (right - left + 1);

      const sum =
        integral[(bottom + 1) * (width + 1) + (right + 1)] -
        integral[top * (width + 1) + (right + 1)] -
        integral[(bottom + 1) * (width + 1) + left] +
        integral[top * (width + 1) + left];

      means[y * width + x] = sum / count;
    }
  }

  return means;
}

/**
 * Pulls the brightest part of each channel up to white.
 *
 * Paper photographed under a kitchen light is yellow-grey, and a global
 * brightness lift keeps it yellow. Scaling each channel separately against its
 * own near-maximum makes the paper white and, as a side effect, the colours on
 * it truer.
 */
function whiteBalance(image) {
  const { data } = image;
  const histograms = [new Uint32Array(256), new Uint32Array(256), new Uint32Array(256)];

  for (let i = 0; i < data.length; i += 4) {
    histograms[0][data[i]] += 1;
    histograms[1][data[i + 1]] += 1;
    histograms[2][data[i + 2]] += 1;
  }

  const pixels = data.length / 4;
  const luts = histograms.map((histogram) => {
    // The 97th percentile rather than the maximum: one blown-out highlight
    // should not set the white point for the whole photo.
    let seen = 0;
    let white = 255;
    for (let value = 0; value < 256; value += 1) {
      seen += histogram[value];
      if (seen >= pixels * 0.97) {
        white = value;
        break;
      }
    }

    const scale = 245 / Math.max(white, 32);
    const lut = new Uint8ClampedArray(256);
    for (let value = 0; value < 256; value += 1) lut[value] = value * scale;
    return lut;
  });

  for (let i = 0; i < data.length; i += 4) {
    data[i] = luts[0][data[i]];
    data[i + 1] = luts[1][data[i + 1]];
    data[i + 2] = luts[2][data[i + 2]];
  }
}

/* ---------------------------------------------------------------- output */

/**
 * Runs one page all the way through: rotate, crop and straighten, then filter.
 *
 * @param {HTMLImageElement} image the loaded original
 * @param {object} page the editable settings — rotation, corners, filter,
 *   brightness, contrast
 * @param {number} maxDimension the long edge of the result
 * @returns {HTMLCanvasElement}
 */
export function renderPage(image, page, maxDimension) {
  // Work at the output size: cropping from a canvas larger than the result only
  // costs memory, and one downscale is sharper than two.
  const source = toCanvas(image, {
    rotation: page.rotation ?? 0,
    maxDimension: Math.round(maxDimension * 1.4),
  });

  const corners = page.corners ?? FULL_FRAME;
  const size = croppedSize(corners, source.width, source.height, maxDimension);
  const cropped = warp(source, corners, size);

  applyFilter(cropped, page);

  const canvas = document.createElement("canvas");
  canvas.width = cropped.width;
  canvas.height = cropped.height;
  canvas.getContext("2d").putImageData(cropped, 0, 0);

  return canvas;
}

/**
 * PNG for the two filters that produce flat areas of one colour, where it wins
 * on both size and sharpness; JPEG for photographs, where PNG would be many
 * times larger for no visible gain.
 */
export function encodingFor(filter) {
  return filter === "bw" || filter === "document"
    ? { type: "image/png", extension: "png" }
    : { type: "image/jpeg", quality: 0.9, extension: "jpg" };
}

export function toBlob(canvas, { type = "image/jpeg", quality = 0.9 } = {}) {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(new Error("The page could not be saved."))),
      type,
      quality,
    );
  });
}

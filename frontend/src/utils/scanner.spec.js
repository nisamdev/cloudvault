import { describe, expect, it } from "vitest";
import { croppedSize, detectPageIn, solveHomography } from "@/utils/scanner";

/**
 * The geometry, which is the part that is silently wrong rather than visibly
 * broken: a homography off by a sign still produces an image, just not of the
 * document.
 */
describe("solveHomography", () => {
  const project = (h, { x, y }) => {
    const w = h[6] * x + h[7] * y + h[8];
    return { x: (h[0] * x + h[1] * y + h[2]) / w, y: (h[3] * x + h[4] * y + h[5]) / w };
  };

  const square = [
    { x: 0, y: 0 },
    { x: 100, y: 0 },
    { x: 100, y: 200 },
    { x: 0, y: 200 },
  ];

  it("maps each corner onto its partner", () => {
    // A page photographed at an angle: the far edge is shorter than the near one.
    const quad = [
      { x: 30, y: 12 },
      { x: 260, y: 40 },
      { x: 240, y: 390 },
      { x: 10, y: 350 },
    ];

    const h = solveHomography(square, quad);

    square.forEach((corner, index) => {
      const mapped = project(h, corner);
      expect(mapped.x).toBeCloseTo(quad[index].x, 6);
      expect(mapped.y).toBeCloseTo(quad[index].y, 6);
    });
  });

  it("keeps straight lines straight", () => {
    const quad = [
      { x: 20, y: 10 },
      { x: 300, y: 60 },
      { x: 280, y: 400 },
      { x: 0, y: 330 },
    ];
    const h = solveHomography(square, quad);

    // Three collinear points in the source stay collinear in the result — the
    // defining property of a projective transform, and the reason a page edge
    // comes out straight rather than bowed.
    const [a, b, c] = [
      { x: 0, y: 0 },
      { x: 50, y: 100 },
      { x: 100, y: 200 },
    ].map((point) => project(h, point));

    const cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    expect(Math.abs(cross)).toBeLessThan(1e-6);
  });

  it("gives up on a degenerate quad rather than returning nonsense", () => {
    const flat = [
      { x: 0, y: 0 },
      { x: 10, y: 0 },
      { x: 20, y: 0 },
      { x: 30, y: 0 },
    ];

    expect(solveHomography(square, flat)).toBeNull();
  });
});

describe("croppedSize", () => {
  it("straightens to the longer of each opposing pair", () => {
    // Near edge 0.8 of the width, far edge 0.5: the page is really as wide as
    // its nearest edge, so that is what it should come out as.
    const corners = [
      { x: 0.25, y: 0 },
      { x: 0.75, y: 0 },
      { x: 0.9, y: 1 },
      { x: 0.1, y: 1 },
    ];

    const size = croppedSize(corners, 1000, 1000, 4000);

    expect(size.width).toBe(800);
    // The sides slope outwards, so they are longer than the page is tall — the
    // straightened height is the side's own length, not the frame's.
    expect(size.height).toBe(Math.round(Math.hypot(150, 1000)));
  });

  it("caps the long edge without distorting the shape", () => {
    const corners = [
      { x: 0, y: 0 },
      { x: 1, y: 0 },
      { x: 1, y: 1 },
      { x: 0, y: 1 },
    ];

    const size = croppedSize(corners, 4000, 2000, 1800);

    expect(size.width).toBe(1800);
    expect(size.height).toBe(900);
  });
});

/**
 * Finding the page. Built as plain greyscale buffers rather than through a
 * canvas — jsdom has none, and the detection is arithmetic either way. The
 * fixture is blurred because the real input is a downscaled photo, and a hard
 * one-pixel edge is not what the detector ever actually sees.
 */
describe("detectPageIn", () => {
  const WIDTH = 240;
  const HEIGHT = 320;

  /** A page of `paper` on a field of `table`, with lines of text across it. */
  function photo({ quad, table = 60, paper = 245, ink = 20 }) {
    const grey = new Float32Array(WIDTH * HEIGHT).fill(table);

    for (let y = 0; y < HEIGHT; y += 1) {
      for (let x = 0; x < WIDTH; x += 1) {
        if (inside(quad, x, y)) grey[y * WIDTH + x] = paper;
      }
    }

    for (let row = 0; row < 12; row += 1) {
      const y = Math.round(HEIGHT * 0.2) + row * 14;
      for (let x = Math.round(WIDTH * 0.28); x < WIDTH * 0.72; x += 1) {
        for (let thickness = 0; thickness < 2; thickness += 1) {
          if (inside(quad, x, y + thickness)) grey[(y + thickness) * WIDTH + x] = ink;
        }
      }
    }

    return soften(grey);
  }

  function inside(quad, x, y) {
    let within = false;
    for (let i = 0, j = quad.length - 1; i < quad.length; j = i, i += 1) {
      const a = quad[i];
      const b = quad[j];
      if (a.y > y !== b.y > y && x < ((b.x - a.x) * (y - a.y)) / (b.y - a.y) + a.x) within = !within;
    }
    return within;
  }

  function soften(grey) {
    const out = new Float32Array(grey.length);

    for (let y = 0; y < HEIGHT; y += 1) {
      for (let x = 0; x < WIDTH; x += 1) {
        let sum = 0;
        let count = 0;
        for (let dy = -1; dy <= 1; dy += 1) {
          for (let dx = -1; dx <= 1; dx += 1) {
            const ny = y + dy;
            const nx = x + dx;
            if (ny < 0 || ny >= HEIGHT || nx < 0 || nx >= WIDTH) continue;
            sum += grey[ny * WIDTH + nx];
            count += 1;
          }
        }
        out[y * WIDTH + x] = sum / count;
      }
    }

    return out;
  }

  /** Furthest a guessed corner sits from the real one, as a fraction of the frame. */
  function worstCorner(got, quad) {
    return Math.max(
      ...got.map((corner, i) =>
        Math.hypot(corner.x - quad[i].x / WIDTH, corner.y - quad[i].y / HEIGHT),
      ),
    );
  }

  const square = [
    { x: 40, y: 40 },
    { x: 200, y: 40 },
    { x: 200, y: 280 },
    { x: 40, y: 280 },
  ];

  it("finds a page lying square to the frame", () => {
    expect(worstCorner(detectPageIn(photo({ quad: square }), WIDTH, HEIGHT), square))
      .toBeLessThan(0.06);
  });

  // The reason corners are found as diagonal extremes rather than as a bounding
  // box: a box around a tilted page has table in all four corners.
  it("follows a page that is tilted", () => {
    const quad = [
      { x: 76, y: 40 },
      { x: 205, y: 84 },
      { x: 168, y: 285 },
      { x: 40, y: 240 },
    ];

    const got = detectPageIn(photo({ quad }), WIDTH, HEIGHT);

    expect(worstCorner(got, quad)).toBeLessThan(0.06);
    // A bounding box would put these two at the same height. The page does not.
    expect(got[1].y - got[0].y).toBeGreaterThan(0.05);
  });

  it("finds a dark document on a pale surface", () => {
    const dark = photo({ quad: square, table: 240, paper: 45, ink: 230 });

    expect(worstCorner(detectPageIn(dark, WIDTH, HEIGHT), square)).toBeLessThan(0.06);
  });

  // Text has paper on both sides of it, so the top line of a page that fills
  // the frame must not be mistaken for the top of the page.
  it("leaves a page that fills the frame alone", () => {
    const quad = [
      { x: 0, y: 0 },
      { x: WIDTH, y: 0 },
      { x: WIDTH, y: HEIGHT },
      { x: 0, y: HEIGHT },
    ];

    expect(worstCorner(detectPageIn(photo({ quad }), WIDTH, HEIGHT), quad)).toBeLessThan(0.06);
  });

  it("gives back the whole frame when there is no page to find", () => {
    const flat = new Float32Array(WIDTH * HEIGHT).fill(128);

    expect(detectPageIn(flat, WIDTH, HEIGHT)).toEqual([
      { x: 0, y: 0 },
      { x: 1, y: 0 },
      { x: 1, y: 1 },
      { x: 0, y: 1 },
    ]);
  });

  it("gives back the whole frame rather than cropping to something too small", () => {
    // A pale table with one small dark object on it. It sits in the middle, so
    // it passes for the page — until its size gives it away.
    const grey = new Float32Array(WIDTH * HEIGHT).fill(235);
    for (let y = Math.round(HEIGHT * 0.36); y < HEIGHT * 0.64; y += 1) {
      for (let x = Math.round(WIDTH * 0.36); x < WIDTH * 0.64; x += 1) grey[y * WIDTH + x] = 40;
    }

    expect(detectPageIn(grey, WIDTH, HEIGHT)).toEqual([
      { x: 0, y: 0 },
      { x: 1, y: 0 },
      { x: 1, y: 1 },
      { x: 0, y: 1 },
    ]);
  });
});

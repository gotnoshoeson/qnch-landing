/**
 * Shared TV-static painter.
 *
 * Every canvas carrying `data-static-field` on the page is driven from here.
 * Attributes on the canvas configure it:
 *
 *   data-px       size of one drawn pixel, in screen px
 *   data-density  share of pixels lit on a frame, 0-1
 *   data-fps      redraws per second
 *   data-mint     "1" to tint ~14% of lit pixels mint
 *
 * ---- why it is built this way -------------------------------------------
 *
 * Regenerating every pixel per frame is fine for a 40px band and ruinous for
 * a full viewport: a 1440x900 hero at pixelSize 3 is ~144k pixels, which is
 * roughly 1.7M Math.random() calls a second, forever, with no settled state
 * to sleep into.
 *
 * So the noise is pre-rendered once into a handful of fixed-size TILES and
 * each frame is a few drawImage blits instead. Two consequences worth
 * knowing:
 *
 * - Tiles live in *noise-pixel* space, not screen space, so they are
 *   completely independent of viewport size. Resizing changes only the main
 *   canvas backing store and the number of blits needed to cover it — no
 *   noise is ever regenerated.
 * - Tiles are cached per (density, mint), so a page running the same settings
 *   in several places pays for one set. Matching the hero and the divider on
 *   scale means they share.
 *
 * Perceived repetition is killed by drawing each frame at a random wrapped
 * offset, which varies the field spatially as well as temporally. That is why
 * eight frames is enough; without the offset it would not be.
 */

/** Tile edge, in noise pixels. Halved on small screens, where the full tile
 *  would be mostly wasted memory. A tile no longer has to be big enough to
 *  cover the viewport by itself — adjacent cells draw *different* frames
 *  (see paint), so nothing repeats within a frame regardless of scale. */
const TILE = typeof window !== 'undefined' && window.innerWidth < 700 ? 128 : 256;

/** Enough distinct frames that the cycle reads as noise rather than a loop,
 *  given the per-frame offset. Eight tiles is ~2MB at TILE 256. */
const FRAMES = 8;

const cache = new Map<string, HTMLCanvasElement[]>();

function buildFrames(density: number, mint: boolean): HTMLCanvasElement[] {
	const key = `${density}|${mint}`;
	const hit = cache.get(key);
	if (hit) return hit;

	const frames: HTMLCanvasElement[] = [];

	for (let f = 0; f < FRAMES; f++) {
		const tile = document.createElement('canvas');
		tile.width = TILE;
		tile.height = TILE;
		const tctx = tile.getContext('2d')!;
		const image = tctx.createImageData(TILE, TILE);
		const d = image.data;

		for (let i = 0; i < TILE * TILE; i++) {
			const o = i * 4;
			if (Math.random() < density) {
				if (mint && Math.random() < 0.14) {
					d[o] = 173;
					d[o + 1] = 235;
					d[o + 2] = 179;
				} else {
					// lit pixels run mid-grey to white
					const v = 96 + ((Math.random() * 160) | 0);
					d[o] = v;
					d[o + 1] = v;
					d[o + 2] = v;
				}
			} else {
				// unlit pixels are not flat black — they carry the low end of the ramp
				const v = (Math.random() * 64) | 0;
				d[o] = v;
				d[o + 1] = v;
				d[o + 2] = v;
			}
			d[o + 3] = 255;
		}

		tctx.putImageData(image, 0, 0);
		frames.push(tile);
	}

	cache.set(key, frames);
	return frames;
}

export function mountStaticFields() {
	const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

	document
		.querySelectorAll<HTMLCanvasElement>('[data-static-field]:not([data-static-mounted])')
		.forEach((canvas) => {
			const ctx = canvas.getContext('2d');
			if (!ctx) return;
			canvas.dataset.staticMounted = '1';

			const px = Number(canvas.dataset.px) || 3;
			const density = Number(canvas.dataset.density) || 0.34;
			const fps = Number(canvas.dataset.fps) || 12;
			const mint = canvas.dataset.mint === '1';

			const frames = buildFrames(density, mint);

			let w = 0;
			let h = 0;
			let cursor = 0;
			let last = 0;
			let raf = 0;

			// Draw small, let CSS scale it up hard. Only this changes on resize.
			const size = () => {
				w = Math.max(1, Math.ceil(canvas.clientWidth / px));
				h = Math.max(1, Math.ceil(canvas.clientHeight / px));
				canvas.width = w;
				canvas.height = h;
				// Backing-store changes reset context state.
				ctx.imageSmoothingEnabled = false;
			};

			const paint = () => {
				// Wrapped offset: tiles land somewhere new every frame, so neither
				// the tiling grid nor the frame cycle settles into a pattern.
				const ox = (Math.random() * TILE) | 0;
				const oy = (Math.random() * TILE) | 0;

				// Each cell takes the next frame rather than all cells sharing one,
				// so a tile is never adjacent to a copy of itself. That is what
				// lets the tile stay small enough to be cheap in memory.
				let f = cursor++;

				for (let y = -oy; y < h; y += TILE) {
					for (let x = -ox; x < w; x += TILE) {
						ctx.drawImage(frames[f++ % frames.length], x, y);
					}
				}
			};

			const tick = (t: number) => {
				if (t - last >= 1000 / fps) {
					last = t;
					paint();
				}
				raf = requestAnimationFrame(tick);
			};

			const start = () => {
				if (reduced || raf) return;
				raf = requestAnimationFrame(tick);
			};

			const stop = () => {
				cancelAnimationFrame(raf);
				raf = 0;
			};

			size();
			paint();
			if (!reduced) start();

			new IntersectionObserver((entries) => {
				entries[0].isIntersecting ? start() : stop();
			}).observe(canvas);

			let resizeTimer: number;
			window.addEventListener('resize', () => {
				clearTimeout(resizeTimer);
				resizeTimer = window.setTimeout(() => {
					size();
					paint();
				}, 120);
			});
		});
}

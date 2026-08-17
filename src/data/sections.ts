/**
 * The site's numbered sections. Each one appears on the landing page and,
 * once built out, gets its own page at /<slug>. The numbers are stable
 * across the whole site — /revenue is 04 wherever it shows up.
 *
 * `ready: false` means the page doesn't exist yet: no "read more" link is
 * rendered on the landing section and the pager skips over it. Flip it to
 * true in the same commit that adds src/pages/<slug>.astro.
 *
 * Section 08 (Start) is deliberately absent — it's a call to action, not a
 * topic, and the install walkthrough already lives in the docs.
 */
export interface SectionMeta {
	n: string;
	slug: string;
	eyebrow: string;
	title: string;
	ready: boolean;
}

export const sections: SectionMeta[] = [
	{ n: '01', slug: 'services', eyebrow: 'Three services', title: 'Three services, no platforms', ready: true },
	{ n: '02', slug: 'setup', eyebrow: 'Setup', title: 'DIY toolkit for DIY musicians', ready: false },
	{ n: '03', slug: 'dashboard', eyebrow: 'The dashboard', title: 'Artist controls', ready: true },
	{ n: '04', slug: 'revenue', eyebrow: 'Revenue split', title: 'Sovereign payments, minimally extractive', ready: true },
	{ n: '05', slug: 'fansociety', eyebrow: 'FanSociety', title: 'Patronage for musicians and fans', ready: true },
	{ n: '06', slug: 'discovery', eyebrow: 'Discovery', title: 'Bye-bye algorithms', ready: true },
	{ n: '07', slug: 'ai', eyebrow: 'Artificial intelligence', title: 'The elephant in the room', ready: true },
];

export function bySlug(slug: string): SectionMeta | undefined {
	return sections.find((s) => s.slug === slug);
}

/** Only ever returns pages that exist, so the pager can't 404. */
export function neighbours(slug: string) {
	const live = sections.filter((s) => s.ready);
	const i = live.findIndex((s) => s.slug === slug);
	return {
		prev: i > 0 ? live[i - 1] : undefined,
		next: i >= 0 && i < live.length - 1 ? live[i + 1] : undefined,
	};
}

// UI-copy hygiene (NFR-10, steering/structure.md). No em-dash or en-dash may
// reach any user-facing string. Bedrock-suggested replies are generated text, so
// the reply layer strips or replaces dashes before the string is ever displayed.

const EM_DASH = '\u2014';
const EN_DASH = '\u2013';
// Also cover the horizontal bar and figure dash which render dash-like.
const FIGURE_DASH = '\u2012';
const HORIZONTAL_BAR = '\u2015';

const DASH_CHARS = `${EM_DASH}${EN_DASH}${FIGURE_DASH}${HORIZONTAL_BAR}`;
// Fresh regex per call site avoids shared lastIndex state from the /g flag.
const DASH_REPLACE = new RegExp(`[${DASH_CHARS}]`, 'g');
const DASH_TEST = new RegExp(`[${DASH_CHARS}]`);

/**
 * Replace em/en dashes (and related long dashes) with a spaced hyphen, then
 * collapse the resulting double spaces. Idempotent and safe on any string.
 */
export function stripDashes(input: string): string {
  return input.replace(DASH_REPLACE, ' - ').replace(/\s{2,}/g, ' ').trim();
}

/** True if a string contains any forbidden dash character (used by lint/tests). */
export function containsForbiddenDash(input: string): boolean {
  // Non-global regex: no lastIndex state, safe to call repeatedly.
  return DASH_TEST.test(input);
}

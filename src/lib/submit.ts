import { SUBMIT_URL } from './config';

export type SubmitResult = { ok: true; id: string } | { ok: false; error: string };

export async function submitPlanting(body: FormData): Promise<SubmitResult> {
  let res: Response;
  try {
    res = await fetch(SUBMIT_URL, { method: 'POST', body });
  } catch {
    return { ok: false, error: 'Network error. Check your connection and try again.' };
  }

  const json = await res.json().catch(() => ({}));
  if (res.ok && typeof json.id === 'string') return { ok: true, id: json.id };
  return { ok: false, error: typeof json.error === 'string' ? json.error : 'Something went wrong. Please try again.' };
}

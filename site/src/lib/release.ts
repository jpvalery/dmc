import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

export const repo = 'jpvalery/dmc';
export const repoUrl = `https://github.com/${repo}`;
export const releasesUrl = `${repoUrl}/releases`;
export const issuesUrl = `${repoUrl}/issues`;
// The release workflow always uploads the image under this name, so the link never changes.
export const downloadUrl = `${releasesUrl}/latest/download/DMC.dmg`;
export const checksumUrl = `${releasesUrl}/latest/download/DMC.dmg.sha256`;

export interface Release {
  version: string | null;
  sizeMB: string | null;
  notesUrl: string;
}

/**
 * The latest GitHub release, read once at build time. The release workflow redeploys the site,
 * so this stays current. When the API is unreachable or rate-limited, the version falls back to
 * the app's Info.plist (Vercel checks out the whole repository), then to nothing.
 */
export async function latestRelease(): Promise<Release> {
  try {
    const headers: Record<string, string> = {
      Accept: 'application/vnd.github+json',
      'User-Agent': 'dmc-site',
    };
    if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
    const res = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, {
      headers,
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) throw new Error(`GitHub answered ${res.status}`);
    const data = await res.json();
    const dmg = (data.assets ?? []).find((a: { name: string }) => a.name === 'DMC.dmg');
    return {
      version: String(data.tag_name).replace(/^v/, ''),
      sizeMB: dmg ? (dmg.size / 1_000_000).toFixed(1) : null,
      notesUrl: data.html_url ?? releasesUrl,
    };
  } catch {
    return { version: await plistVersion(), sizeMB: null, notesUrl: releasesUrl };
  }
}

async function plistVersion(): Promise<string | null> {
  try {
    // Relative to the site folder, where every build runs; import.meta.url moves when bundled.
    const plist = await readFile(resolve(process.cwd(), '../app/Resources/Info.plist'), 'utf8');
    return plist.match(/CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/)?.[1] ?? null;
  } catch {
    return null;
  }
}

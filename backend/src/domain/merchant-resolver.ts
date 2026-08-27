const aliases: Record<string, string> = {
  "netflix com": "Netflix", netflix: "Netflix", "spotify usa": "Spotify", spotify: "Spotify",
  "adobe systems": "Adobe", adobe: "Adobe", "apple com bill icloud": "iCloud+", openai: "ChatGPT",
  "youtube premium": "YouTube Premium", "google youtube": "YouTube Premium", "microsoft 365": "Microsoft 365",
  "amazon prime": "Amazon Prime", dropbox: "Dropbox", canva: "Canva", hulu: "Hulu", disney: "Disney+"
};
export function normalizeMerchant(raw: string): { canonicalName: string; confidence: number; needsReview: boolean } {
  const normalized = raw.toLowerCase().replace(/\d{4,}/g, " ").replace(/[^a-z+ ]/g, " ").replace(/\s+/g, " ").trim();
  // Apple combines unrelated App Store purchases under this descriptor. Never guess the service.
  if (/^apple com bill(?:\s|$)/.test(normalized) && !normalized.includes("icloud")) {
    return { canonicalName: "Apple purchase", confidence: 0.15, needsReview: true };
  }
  const exact = aliases[normalized];
  if (exact) return { canonicalName: exact, confidence: 1, needsReview: false };
  const match = Object.entries(aliases).find(([alias]) => normalized.includes(alias));
  if (match) return { canonicalName: match[1], confidence: 0.92, needsReview: false };
  return { canonicalName: raw.trim(), confidence: 0.35, needsReview: true };
}

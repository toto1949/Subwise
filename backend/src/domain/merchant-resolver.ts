const aliases: Record<string, string> = {
  "netflix com": "Netflix", netflix: "Netflix", "spotify usa": "Spotify", spotify: "Spotify",
  "adobe systems": "Adobe", adobe: "Adobe", "apple com bill icloud": "iCloud+", openai: "ChatGPT"
};
export function normalizeMerchant(raw: string): { canonicalName: string; confidence: number } {
  const normalized = raw.toLowerCase().replace(/\d{4,}/g, " ").replace(/[^a-z+ ]/g, " ").replace(/\s+/g, " ").trim();
  const exact = aliases[normalized];
  if (exact) return { canonicalName: exact, confidence: 1 };
  const match = Object.entries(aliases).find(([alias]) => normalized.includes(alias));
  if (match) return { canonicalName: match[1], confidence: 0.92 };
  return { canonicalName: raw.trim(), confidence: 0.35 };
}

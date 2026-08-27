import type { Config } from "../config.js";
import { AppError } from "../lib/errors.js";
import type { DetectionTransaction, PlaidRecurringStream } from "../domain/subscription-detection.js";

type PlaidErrorBody = { error_code?: string; error_message?: string; request_id?: string };

export class PlaidClient {
  private readonly baseURL: string;
  constructor(private readonly config: Config) {
    this.baseURL = `https://${config.PLAID_ENV}.plaid.com`;
  }

  get isConfigured() {
    return Boolean(this.config.PLAID_CLIENT_ID && this.config.PLAID_SECRET && this.config.PLAID_REDIRECT_URI && this.config.DATA_ENCRYPTION_KEY);
  }

  async createLinkToken(userId: string) {
    this.assertConfigured();
    return this.post<{ link_token: string; expiration: string; request_id: string }>("/link/token/create", {
      client_name: "SubWise",
      language: "en",
      country_codes: ["US"],
      products: ["transactions"],
      user: { client_user_id: userId },
      transactions: { days_requested: 730 },
      redirect_uri: this.config.PLAID_REDIRECT_URI
    });
  }

  async exchangePublicToken(publicToken: string) {
    this.assertConfigured();
    return this.post<{ access_token: string; item_id: string; request_id: string }>("/item/public_token/exchange", { public_token: publicToken });
  }

  async recurring(accessToken: string) {
    return this.post<{ outflow_streams: PlaidRecurringStream[]; request_id: string }>("/transactions/recurring/get", { access_token: accessToken });
  }

  async sync(accessToken: string): Promise<DetectionTransaction[]> {
    let cursor: string | undefined;
    let hasMore = true;
    const items: DetectionTransaction[] = [];
    while (hasMore) {
      const result = await this.post<{ added: PlaidSyncTransaction[]; modified: PlaidSyncTransaction[]; next_cursor: string; has_more: boolean }>("/transactions/sync", {
        access_token: accessToken,
        ...(cursor ? { cursor } : {}),
        count: 500
      });
      for (const item of [...result.added, ...result.modified]) {
        items.push({
          id: item.transaction_id,
          name: item.name,
          merchantName: item.merchant_name,
          amount: item.amount,
          date: item.date,
          category: item.personal_finance_category?.primary
        });
      }
      cursor = result.next_cursor;
      hasMore = result.has_more;
    }
    return items;
  }

  private assertConfigured() {
    if (!this.isConfigured) throw new AppError("PLAID_NOT_CONFIGURED", "Bank connection is not configured on this server yet.", 503);
  }

  private async post<T>(path: string, body: Record<string, unknown>): Promise<T> {
    this.assertConfigured();
    const response = await fetch(this.baseURL + path, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "PLAID-CLIENT-ID": this.config.PLAID_CLIENT_ID!,
        "PLAID-SECRET": this.config.PLAID_SECRET!
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(20_000)
    });
    const result = await response.json() as T | PlaidErrorBody;
    if (!response.ok) {
      const plaidError = result as PlaidErrorBody;
      const retryable = response.status >= 500 ? 502 : 422;
      throw new AppError(plaidError.error_code || "PLAID_REQUEST_FAILED", plaidError.error_message || "Plaid could not complete this request.", retryable);
    }
    return result as T;
  }
}

type PlaidSyncTransaction = {
  transaction_id: string; name: string; merchant_name?: string | null; amount: number; date: string;
  personal_finance_category?: { primary?: string | null } | null;
};

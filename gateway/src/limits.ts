// İstek sınırlandırma ve maliyet kontrolü (bellek içi; gateway yeniden
// başlatılınca günlük sayaçlar sıfırlanır — README'de belirtilmiştir).

export class RateLimiter {
  private readonly hits = new Map<string, number[]>();
  private readonly perMinute: number;
  private readonly now: () => number;

  constructor(perMinute: number, now: () => number = Date.now) {
    this.perMinute = perMinute;
    this.now = now;
  }

  /** İzin verilirse true ve isteği kaydeder. */
  tryAcquire(key: string): boolean {
    const t = this.now();
    const recent = (this.hits.get(key) ?? []).filter((x) => t - x < 60_000);
    if (recent.length >= this.perMinute) {
      this.hits.set(key, recent);
      return false;
    }
    recent.push(t);
    this.hits.set(key, recent);
    return true;
  }
}

export interface UsageSnapshot {
  day: string;
  requestsToday: number;
  costTodayUsd: number;
}

export class UsageLedger {
  private day = '';
  private requests = 0;
  private cost = 0;
  private readonly now: () => number;

  constructor(now: () => number = Date.now) {
    this.now = now;
  }

  private roll(): void {
    const d = new Date(this.now()).toISOString().slice(0, 10);
    if (d !== this.day) {
      this.day = d;
      this.requests = 0;
      this.cost = 0;
    }
  }

  snapshot(): UsageSnapshot {
    this.roll();
    return { day: this.day, requestsToday: this.requests, costTodayUsd: this.cost };
  }

  recordRequest(): void {
    this.roll();
    this.requests += 1;
  }

  recordCost(usd: number): void {
    this.roll();
    this.cost += usd;
  }
}

export function costUsd(inputTokens: number, outputTokens: number, inPerM: number, outPerM: number): number {
  return (inputTokens * inPerM + outputTokens * outPerM) / 1_000_000;
}

/** Kaba üst sınır tahmini: ~3 karakter = 1 token (Türkçe için ihtiyatlı). */
export function estimateInputTokens(chars: number): number {
  return Math.ceil(chars / 3);
}

// convex/lib/rateLimit.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Attempt limiting for authentication (login, password reset).
//
// Runs inside mutations, so every read-modify-write is a serializable Convex transaction:
// concurrent attempts cannot slip past the counter.
// IMPORTANT: callers must RETURN a failure result after recording a failure (not throw),
// otherwise the counter write is rolled back with the rest of the mutation.
// ═══════════════════════════════════════════════════════════════════════

export type LimitPolicy = {
  max: number; // allowed events per window
  windowMs: number; // counting window
  lockMs?: number; // lock duration once `max` is reached (defaults to windowMs)
};

async function getRow(ctx: { db: any }, key: string) {
  return await ctx.db.query("auth_rate_limits").withIndex("by_key", (q: any) => q.eq("key", key)).first();
}

/** Remaining lock time in ms (0 when not locked). */
export async function lockRemainingMs(ctx: { db: any }, key: string, now = Date.now()): Promise<number> {
  const row = await getRow(ctx, key);
  return row?.lockedUntil && row.lockedUntil > now ? row.lockedUntil - now : 0;
}

/** Records one failed attempt. Returns the lock time in ms if this attempt triggered/extends a lock. */
export async function recordFailure(ctx: { db: any }, key: string, policy: LimitPolicy, now = Date.now()): Promise<number> {
  const row = await getRow(ctx, key);
  const lockMs = policy.lockMs ?? policy.windowMs;
  if (!row) {
    const locked = policy.max <= 1;
    await ctx.db.insert("auth_rate_limits", {
      key,
      count: 1,
      windowStart: now,
      lockedUntil: locked ? now + lockMs : undefined,
      updatedAt: now,
    });
    return locked ? lockMs : 0;
  }
  const inWindow = now - row.windowStart < policy.windowMs;
  const count = inWindow ? row.count + 1 : 1;
  const windowStart = inWindow ? row.windowStart : now;
  const lockedUntil = count >= policy.max ? now + lockMs : row.lockedUntil;
  await ctx.db.patch(row._id, { count, windowStart, lockedUntil, updatedAt: now });
  return lockedUntil && lockedUntil > now ? lockedUntil - now : 0;
}

/**
 * Consumes one unit of a request budget (e.g. "3 reset emails per 15 minutes").
 * Returns false (and writes nothing) when the budget is exhausted.
 */
export async function consume(ctx: { db: any }, key: string, policy: LimitPolicy, now = Date.now()): Promise<boolean> {
  const row = await getRow(ctx, key);
  if (!row) {
    await ctx.db.insert("auth_rate_limits", { key, count: 1, windowStart: now, updatedAt: now });
    return true;
  }
  if (now - row.windowStart >= policy.windowMs) {
    await ctx.db.patch(row._id, { count: 1, windowStart: now, lockedUntil: undefined, updatedAt: now });
    return true;
  }
  if (row.count >= policy.max) return false;
  await ctx.db.patch(row._id, { count: row.count + 1, updatedAt: now });
  return true;
}

/** Clears a key after a successful authentication. */
export async function clearLimit(ctx: { db: any }, key: string): Promise<void> {
  const row = await getRow(ctx, key);
  if (row) await ctx.db.delete(row._id);
}

export const minutes = (ms: number) => Math.max(1, Math.ceil(ms / 60000));

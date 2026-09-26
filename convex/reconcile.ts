// convex/reconcile.ts
import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const inspectAhmedTopUp = query({
  args: {},
  handler: async (ctx) => {
    // 1. Locate user by phone candidates or name
    const phones = ["073213055", "23273623761", "+23273623761", "073623761", "23273213055"];
    let users = [];
    for (const p of phones) {
      const u = await ctx.db
        .query("users")
        .withIndex("by_phone", (q) => q.eq("phone", p))
        .collect();
      users.push(...u);
    }
    // Also search by name
    const allUsers = await ctx.db.query("users").collect();
    const ahmedUsers = allUsers.filter(
      (u) =>
        (u.name && u.name.toLowerCase().includes("ahmed")) ||
        (u.phone && phones.some((p) => u.phone.includes(p)))
    );

    // 2. Locate any transactions matching order number or reference
    const orderNums = [
      "PW6T3PHPUAA1",
      "PW6T-3PHP-UAA1",
      "vktlx§monime§1790337156421§xab06r",
      "vktlx_monime_1790337156421_xab06r",
      "1790337156421",
    ];

    const allTransactions = await ctx.db.query("transactions").collect();
    const matchedTxns = allTransactions.filter((tx) => {
      const matchTxId = tx.transactionId && orderNums.some((on) => tx.transactionId!.includes(on));
      const matchGtwRef = tx.gatewayReference && orderNums.some((on) => tx.gatewayReference!.includes(on));
      const matchDesc = tx.description && orderNums.some((on) => tx.description!.includes(on));
      return matchTxId || matchGtwRef || matchDesc;
    });

    // 3. User wallets
    const wallets = [];
    for (const u of ahmedUsers) {
      const userWallets = await ctx.db
        .query("walletBalances")
        .withIndex("by_user", (q) => q.eq("userId", u._id))
        .collect();
      wallets.push({ userId: u._id, userName: u.name, userPhone: u.phone, userWallets });
    }

    return {
      ahmedUsers,
      matchedTxns,
      wallets,
      recentTxnsCount: allTransactions.length,
      recentTxns: allTransactions.slice(-10),
    };
  },
});

export const creditAhmedTopUp = mutation({
  args: {
    orderNumber: v.optional(v.string()),
    monimeReference: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const orderNum = args.orderNumber ?? "PW6T3PHPUAA1";
    const rawRef = args.monimeReference ?? "vktlx§monime§1790337156421§xab06r";
    const cleanRef = rawRef.replace(/§/g, "_");
    const grossAmount = 5.00;
    const feeAmount = 0.05;
    const netAmount = 4.95;
    const currency = "SLE";
    const now = Date.now();

    // Reset unintended transaction on Client 3761 if created
    const strayTx = await ctx.db
      .query("transactions")
      .withIndex("by_transaction_id", (q) => q.eq("transactionId", orderNum))
      .first();
    if (strayTx && strayTx.userId !== "jx760xc0621p5tgwphtfn2r98h8ex3be") {
      const strayWallet = await ctx.db.get(strayTx.walletId);
      if (strayWallet) {
        await ctx.db.patch(strayWallet._id, {
          availableBalance: Math.max(0, strayWallet.availableBalance - netAmount),
          updatedAt: now,
        });
      }
      await ctx.db.delete(strayTx._id);
    }

    // 1. Locate user Ahmed J Kamara by ID
    const ahmedId = ctx.db.normalizeId("users", "jx760xc0621p5tgwphtfn2r98h8ex3be");
    const user = ahmedId ? await ctx.db.get(ahmedId) : null;

    if (!user) {
      throw new Error("Could not find user Ahmed J Kamara");
    }

    // 2. Fetch or create user wallet
    let wallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user_currency", (q) =>
        q.eq("userId", user._id).eq("currency", currency)
      )
      .first();

    if (!wallet) {
      throw new Error("Ahmed J Kamara wallet not found");
    }

    const oldAvailable = wallet.availableBalance;
    const newAvailable = Math.round((oldAvailable + netAmount) * 100) / 100;
    const oldEscrow = wallet.escrowBalance ?? 0;
    const newEscrow = Math.round((oldEscrow + netAmount) * 100) / 100;

    await ctx.db.patch(wallet._id, {
      availableBalance: newAvailable,
      escrowBalance: newEscrow,
      updatedAt: now,
    });

    // 3. Find the pending transaction js76djf7kxqtt0kgvxy4q8fd8s8f3rmq
    let targetTx = await ctx.db
      .query("transactions")
      .withIndex("by_transaction_id", (q) => q.eq("transactionId", "vktlx_monime_1790337156421_xab06r"))
      .first();

    if (!targetTx) {
      targetTx = await ctx.db
        .query("transactions")
        .withIndex("by_user", (q) => q.eq("userId", user._id))
        .filter((q) => q.eq(q.field("amount"), 5))
        .first();
    }

    let updatedTxId;
    if (targetTx) {
      await ctx.db.patch(targetTx._id, {
        status: "completed",
        amount: grossAmount,
        netAmount,
        feeAmount,
        currency,
        gatewayProvider: "MONIME_ORANGE",
        gatewayReference: cleanRef,
        description: `MoniMe Top-Up — SLE ${grossAmount.toFixed(2)} (Net: SLE ${netAmount.toFixed(2)}) via Orange Money [Order: ${orderNum}]`,
        updatedAt: now,
      });
      updatedTxId = targetTx._id;
    } else {
      updatedTxId = await ctx.db.insert("transactions", {
        transactionId: orderNum,
        walletId: wallet._id,
        userId: user._id,
        type: "top_up",
        amount: grossAmount,
        netAmount,
        feeAmount,
        currency,
        gatewayProvider: "MONIME_ORANGE",
        gatewayReference: cleanRef,
        status: "completed",
        description: `MoniMe Top-Up — SLE ${grossAmount.toFixed(2)} (Net: SLE ${netAmount.toFixed(2)}) via Orange Money [Order: ${orderNum}]`,
        createdAt: now,
        updatedAt: now,
      });
    }

    return {
      success: true,
      userId: user._id,
      userName: user.name,
      userPhone: user.phone,
      oldAvailableBalance: oldAvailable,
      newAvailableBalance: newAvailable,
      creditedNetAmount: netAmount,
      feeDeducted: feeAmount,
      transactionId: updatedTxId,
      orderNumber: orderNum,
      reference: cleanRef,
    };
  },
});

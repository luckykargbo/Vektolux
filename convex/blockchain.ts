// convex/blockchain.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Web3 Relayer: On-Chain Transaction Logging
// Uses Ethers.js v6 inside a Convex Action to call MarketplaceAuditLedger.sol
// on Polygon PoS or Base L2 (EVM-compatible chains).
// ═══════════════════════════════════════════════════════════════════════

import { v } from "convex/values";
import { internalAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { Id } from "./_generated/dataModel";

// ─── CONTRACT ABI (MarketplaceAuditLedger.sol — minimal interface) ───

const AUDIT_LEDGER_ABI = [
  "function logTransaction(bytes32 dealHash, address buyer, address seller, uint8 dealType, string calldata convexId) external",
  "function isLogged(bytes32 dealHash) public view returns (bool)",
  "event TransactionLogged(bytes32 indexed dealHash, address indexed buyer, address indexed seller, uint8 dealType, uint256 timestamp, string convexId)",
];

// ─── DEAL TYPE MAPPING ───────────────────────────────────────────────

/** Maps Convex referenceType strings to Solidity DealType enum values. */
const DEAL_TYPE_MAP: Record<string, number> = {
  property_sale: 0, // DealType.PROPERTY_SALE
  property_booking: 0, // Treated as property sale
  long_term_rent: 1, // DealType.PROPERTY_LONG_TERM_RENT
  hourly_guesthouse: 2, // DealType.HOURLY_GUESTHOUSE
  vehicle_sale: 3, // DealType.VEHICLE_SALE
  vehicle_rental: 4, // DealType.VEHICLE_RENTAL
  ride_hailing: 5, // DealType.RIDE_HAILING
  ride: 5, // Alias for ride_hailing
};

// ═══════════════════════════════════════════════════════════════════════
//           INTERNAL ACTION: Log Transaction On-Chain
// ═══════════════════════════════════════════════════════════════════════

/**
 * Called by `payments.processVerifiedPayment` via `ctx.scheduler.runAfter(0, ...)`.
 *
 * This action:
 * 1. Constructs a deterministic deal hash from transaction data
 * 2. Connects to the configured EVM RPC provider (Polygon/Base)
 * 3. Calls MarketplaceAuditLedger.logTransaction() using the relayer wallet
 * 4. Stores the resulting blockchain tx hash back in Convex
 *
 * If the on-chain call fails, the error is logged but does NOT block
 * the payment flow (the Convex payment is already confirmed).
 */
export const logTransactionOnChain = internalAction({
  args: {
    paymentIntentId: v.id("paymentIntents"),
    dealType: v.string(),
    buyerId: v.id("users"),
    sellerId: v.id("users"),
    amount: v.number(),
    currency: v.string(),
    gatewayReference: v.string(),
  },
  handler: async (
    ctx,
    args
  ): Promise<{
    success: boolean;
    reason?: string;
    txHash?: string;
    dealHash?: string;
    blockNumber?: number;
    alreadyLogged?: boolean;
    gasUsed?: string;
    code?: string;
  }> => {
    // ── Environment validation ────────────────────────────────────
    const RPC_URL = process.env.BLOCKCHAIN_RPC_URL;
    const RELAYER_PRIVATE_KEY = process.env.RELAYER_PRIVATE_KEY;
    const AUDIT_LEDGER_ADDRESS = process.env.AUDIT_LEDGER_CONTRACT_ADDRESS;

    if (!RPC_URL || !RELAYER_PRIVATE_KEY || !AUDIT_LEDGER_ADDRESS) {
      console.warn(
        "Blockchain: Missing environment variables — skipping on-chain logging.",
        {
          hasRpc: !!RPC_URL,
          hasKey: !!RELAYER_PRIVATE_KEY,
          hasContract: !!AUDIT_LEDGER_ADDRESS,
        }
      );
      return {
        success: false,
        reason: "Blockchain environment not configured",
      };
    }

    try {
      // ── Dynamic import of ethers.js v6 ──────────────────────────
      // Convex Actions support npm packages; ethers is installed in the project
      const { ethers } = await import("ethers");

      // ── Connect to EVM chain ────────────────────────────────────
      const provider = new ethers.JsonRpcProvider(RPC_URL);
      const relayerWallet = new ethers.Wallet(RELAYER_PRIVATE_KEY, provider);

      const auditLedger = new ethers.Contract(
        AUDIT_LEDGER_ADDRESS,
        AUDIT_LEDGER_ABI,
        relayerWallet
      );

      // ── Construct deterministic deal hash ───────────────────────
      // Hash = keccak256(paymentIntentId || dealType || amount || currency || gatewayRef || timestamp)
      const dealHash: string = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["string", "string", "uint256", "string", "string"],
          [
            args.paymentIntentId,
            args.dealType,
            Math.round(args.amount),
            args.currency,
            args.gatewayReference,
          ]
        )
      );

      // ── Check if already logged (idempotency) ──────────────────
      const alreadyLogged: boolean = await auditLedger.isLogged(dealHash);
      if (alreadyLogged) {
        console.log(
          `Blockchain: Deal ${dealHash} already logged — skipping duplicate`
        );
        return {
          success: true,
          alreadyLogged: true,
          dealHash,
        };
      }

      // ── Resolve buyer/seller wallet addresses ──────────────────
      // If users have wallet addresses, use them; otherwise use relayer as proxy
      const buyer: { walletAddress?: string | null; name?: string } | null =
        await ctx.runQuery(internal.payments.getUserWalletAddress, {
          userId: args.buyerId,
        });
      const seller: { walletAddress?: string | null; name?: string } | null =
        await ctx.runQuery(internal.payments.getUserWalletAddress, {
          userId: args.sellerId,
        });

      const buyerAddress: string =
        buyer?.walletAddress ?? relayerWallet.address;
      const sellerAddress: string =
        seller?.walletAddress ?? relayerWallet.address;

      // ── Map deal type to Solidity enum ──────────────────────────
      const dealTypeEnum = DEAL_TYPE_MAP[args.dealType] ?? 5; // Default: RIDE_HAILING

      // ── Estimate gas & send transaction ─────────────────────────
      const gasEstimate = await auditLedger.logTransaction.estimateGas(
        dealHash,
        buyerAddress,
        sellerAddress,
        dealTypeEnum,
        args.paymentIntentId // convexId for cross-reference
      );

      // Add 20% gas buffer for safety
      const gasLimit = (gasEstimate * 120n) / 100n;

      const tx: any = await auditLedger.logTransaction(
        dealHash,
        buyerAddress,
        sellerAddress,
        dealTypeEnum,
        args.paymentIntentId,
        { gasLimit }
      );

      console.log(
        `Blockchain: Transaction submitted — hash: ${tx.hash}, dealHash: ${dealHash}`
      );

      // ── Wait for confirmation (1 block) ─────────────────────────
      const receipt = await tx.wait(1);

      if (!receipt || receipt.status === 0) {
        console.error(
          `Blockchain: Transaction reverted — hash: ${tx.hash}`
        );
        return {
          success: false,
          reason: "Transaction reverted on-chain",
          txHash: tx.hash,
        };
      }

      console.log(
        `Blockchain: Transaction confirmed — hash: ${tx.hash}, block: ${receipt.blockNumber}, gas: ${receipt.gasUsed.toString()}`
      );

      // ── Store tx hash back in Convex ────────────────────────────
      await ctx.runMutation(internal.payments.updateBlockchainHash, {
        paymentIntentId: args.paymentIntentId,
        blockchainTxHash: tx.hash,
      });

      return {
        success: true,
        txHash: tx.hash,
        dealHash,
        blockNumber: receipt.blockNumber,
        gasUsed: receipt.gasUsed.toString(),
      };
    } catch (error: any) {
      // ── Non-blocking error handling ─────────────────────────────
      // Blockchain logging is secondary to the payment flow.
      // Log the error for investigation but don't fail the payment.
      console.error("Blockchain: On-chain logging failed:", {
        error: error.message ?? error,
        paymentIntentId: args.paymentIntentId,
        dealType: args.dealType,
        code: error.code,
        reason: error.reason,
      });

      return {
        success: false,
        reason: error.message ?? "Unknown blockchain error",
        code: error.code,
      };
    }
  },
});

// ═══════════════════════════════════════════════════════════════════════
//       INTERNAL ACTION: Batch Log Multiple Transactions
// ═══════════════════════════════════════════════════════════════════════

/**
 * Batch log multiple deal hashes on-chain in a single transaction.
 * Used for periodic batch reconciliation or backfilling.
 */
export const batchLogOnChain = internalAction({
  args: {
    transactions: v.array(
      v.object({
        paymentIntentId: v.id("paymentIntents"),
        dealType: v.string(),
        buyerAddress: v.string(),
        sellerAddress: v.string(),
        amount: v.number(),
        currency: v.string(),
        gatewayReference: v.string(),
      })
    ),
  },
  handler: async (
    ctx,
    args
  ): Promise<{
    success: boolean;
    txHash?: string;
    count?: number;
    blockNumber?: number;
    reason?: string;
  }> => {
    const RPC_URL = process.env.BLOCKCHAIN_RPC_URL;
    const RELAYER_PRIVATE_KEY = process.env.RELAYER_PRIVATE_KEY;
    const AUDIT_LEDGER_ADDRESS = process.env.AUDIT_LEDGER_CONTRACT_ADDRESS;

    if (!RPC_URL || !RELAYER_PRIVATE_KEY || !AUDIT_LEDGER_ADDRESS) {
      console.warn("Blockchain batch: Missing env vars — skipping.");
      return { success: false, reason: "Not configured" };
    }

    if (args.transactions.length === 0 || args.transactions.length > 50) {
      return { success: false, reason: "Batch size must be 1–50" };
    }

    try {
      const { ethers } = await import("ethers");

      const provider = new ethers.JsonRpcProvider(RPC_URL);
      const wallet = new ethers.Wallet(RELAYER_PRIVATE_KEY, provider);

      // Batch ABI
      const BATCH_ABI = [
        "function logTransactionBatch(bytes32[] calldata dealHashes, address[] calldata buyers, address[] calldata sellers, uint8[] calldata dealTypes, string[] calldata convexIds) external",
      ];

      const contract = new ethers.Contract(
        AUDIT_LEDGER_ADDRESS,
        BATCH_ABI,
        wallet
      );

      // Build batch arrays
      const dealHashes: string[] = [];
      const buyers: string[] = [];
      const sellers: string[] = [];
      const dealTypes: number[] = [];
      const convexIds: string[] = [];

      for (const txn of args.transactions) {
        const hash = ethers.keccak256(
          ethers.AbiCoder.defaultAbiCoder().encode(
            ["string", "string", "uint256", "string", "string"],
            [
              txn.paymentIntentId,
              txn.dealType,
              Math.round(txn.amount),
              txn.currency,
              txn.gatewayReference,
            ]
          )
        );

        dealHashes.push(hash);
        buyers.push(txn.buyerAddress);
        sellers.push(txn.sellerAddress);
        dealTypes.push(DEAL_TYPE_MAP[txn.dealType] ?? 5);
        convexIds.push(txn.paymentIntentId);
      }

      const tx: any = await contract.logTransactionBatch(
        dealHashes,
        buyers,
        sellers,
        dealTypes,
        convexIds
      );

      const receipt = await tx.wait(1);

      console.log(
        `Blockchain batch: ${args.transactions.length} transactions logged. Hash: ${tx.hash}`
      );

      // Update all payment intents with blockchain hash
      for (const txn of args.transactions) {
        await ctx.runMutation(internal.payments.updateBlockchainHash, {
          paymentIntentId: txn.paymentIntentId,
          blockchainTxHash: tx.hash,
        });
      }

      return {
        success: true,
        txHash: tx.hash,
        count: args.transactions.length,
        blockNumber: receipt.blockNumber,
      };
    } catch (error: any) {
      console.error("Blockchain batch error:", error.message);
      return { success: false, reason: error.message };
    }
  },
});

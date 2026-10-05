// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title EscrowManager
 * @author Vektolux Engineering
 * @notice Holds booking deposits, vehicle reservation fees, and property sale
 *         escrows in stablecoins (USDT/USDC) or native crypto (MATIC/ETH)
 *         until checkout/delivery verification conditions are met.
 * @dev Security stack:
 *      - ReentrancyGuard on all state-changing payment functions
 *      - Pausable circuit breaker for emergency freeze
 *      - AccessControl for role-based permissioning
 *      - SafeERC20 for non-standard ERC20 compatibility (USDT)
 *      - Pull-over-push pattern for native crypto refunds
 *
 *      ESCROW LIFECYCLE:
 *      Created → [Funded] → Released (to seller) OR Refunded (to buyer)
 *                         → Disputed → Resolved (admin)
 *                         → Expired → Refunded (auto or manual)
 */
contract EscrowManager is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════
    //                          CONSTANTS & ROLES
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Role for the Convex backend relayer that creates and manages escrows.
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    /// @notice Role for platform admins who can resolve disputes and pause.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Role for dispute arbitrators who can resolve contested escrows.
    bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");

    /// @notice Address(0) sentinel used to represent native crypto (MATIC/ETH).
    address public constant NATIVE_TOKEN = address(0);

    /// @notice Maximum escrow duration before auto-expiry eligibility (30 days).
    uint256 public constant MAX_ESCROW_DURATION = 30 days;

    /// @notice Minimum escrow duration (1 hour — for hourly guesthouse bookings).
    uint256 public constant MIN_ESCROW_DURATION = 1 hours;

    /// @notice Platform fee in basis points (e.g., 250 = 2.5%).
    uint256 public platformFeeBps;

    /// @notice Address receiving platform commission fees.
    address public feeRecipient;

    // ═══════════════════════════════════════════════════════════════════
    //                              ENUMS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Possible states of an escrow.
    enum EscrowStatus {
        CREATED,    // 0 — Escrow created, awaiting funding
        FUNDED,     // 1 — Funds deposited and locked
        RELEASED,   // 2 — Funds released to seller (completed)
        REFUNDED,   // 3 — Funds returned to buyer
        DISPUTED,   // 4 — Under dispute arbitration
        EXPIRED     // 5 — Past deadline, eligible for refund
    }

    /// @notice Type of marketplace escrow.
    enum EscrowType {
        PROPERTY_SALE,           // 0
        PROPERTY_RENTAL_DEPOSIT, // 1
        GUESTHOUSE_BOOKING,      // 2
        VEHICLE_SALE,            // 3
        VEHICLE_RENTAL_DEPOSIT,  // 4
        RIDE_HAILING_HOLD        // 5
    }

    // ═══════════════════════════════════════════════════════════════════
    //                             STRUCTS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Full escrow record stored on-chain.
    /// @param bookingId    Unique identifier from Convex backend.
    /// @param buyer        Address of the payer / renter / passenger.
    /// @param seller       Address of the payee / property owner / driver.
    /// @param token        ERC20 token address, or address(0) for native crypto.
    /// @param amount       Total escrow amount (before platform fee).
    /// @param platformFee  Calculated platform fee at creation time.
    /// @param escrowType   Category of the escrow.
    /// @param status       Current lifecycle status.
    /// @param createdAt    Block timestamp of escrow creation.
    /// @param expiresAt    Deadline after which the escrow can be auto-refunded.
    /// @param convexId     Off-chain Convex document ID for cross-referencing.
    struct Escrow {
        bytes32 bookingId;
        address buyer;
        address seller;
        address token;
        uint256 amount;
        uint256 platformFee;
        EscrowType escrowType;
        EscrowStatus status;
        uint64 createdAt;
        uint64 expiresAt;
        string convexId;
    }

    // ═══════════════════════════════════════════════════════════════════
    //                              STORAGE
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Maps booking ID to its escrow record.
    mapping(bytes32 => Escrow) private _escrows;

    /// @notice Tracks whether a booking ID has been used.
    mapping(bytes32 => bool) public escrowExists;

    /// @notice Whitelist of accepted ERC20 token addresses for escrow.
    mapping(address => bool) public acceptedTokens;

    /// @notice Total number of escrows created.
    uint256 public totalEscrows;

    /// @notice Total value currently locked across all active escrows (per token).
    mapping(address => uint256) public totalLockedByToken;

    // ═══════════════════════════════════════════════════════════════════
    //                              EVENTS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Emitted when a new escrow is created and funded.
    event EscrowCreated(
        bytes32 indexed bookingId,
        address indexed buyer,
        address indexed seller,
        address token,
        uint256 amount,
        uint256 platformFee,
        EscrowType escrowType,
        uint64 expiresAt,
        string convexId
    );

    /// @notice Emitted when escrow funds are released to the seller.
    event FundsReleased(
        bytes32 indexed bookingId,
        address indexed seller,
        uint256 sellerPayout,
        uint256 platformFee
    );

    /// @notice Emitted when escrow funds are refunded to the buyer.
    event BuyerRefunded(
        bytes32 indexed bookingId,
        address indexed buyer,
        uint256 refundAmount
    );

    /// @notice Emitted when an escrow enters dispute status.
    event EscrowDisputed(
        bytes32 indexed bookingId,
        address indexed initiator,
        string reason
    );

    /// @notice Emitted when a dispute is resolved by an arbitrator.
    event DisputeResolved(
        bytes32 indexed bookingId,
        address indexed arbitrator,
        bool releasedToSeller,
        uint256 buyerRefund,
        uint256 sellerPayout
    );

    /// @notice Emitted when the platform fee rate is updated.
    event PlatformFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);

    /// @notice Emitted when a token is added/removed from the accepted list.
    event TokenAcceptanceUpdated(address indexed token, bool accepted);

    // ═══════════════════════════════════════════════════════════════════
    //                              ERRORS
    // ═══════════════════════════════════════════════════════════════════

    error EscrowAlreadyExists(bytes32 bookingId);
    error EscrowNotFound(bytes32 bookingId);
    error InvalidAddress();
    error InvalidAmount();
    error InvalidDuration();
    error InvalidFee(uint256 feeBps);
    error InvalidStatus(EscrowStatus current, EscrowStatus required);
    error TokenNotAccepted(address token);
    error InsufficientNativeValue(uint256 sent, uint256 required);
    error EscrowNotExpired(bytes32 bookingId);
    error TransferFailed();
    error BuyerCannotBeSeller();

    // ═══════════════════════════════════════════════════════════════════
    //                           CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Initializes the EscrowManager with admin, relayer, fee config,
    ///         and accepted stablecoin addresses.
    /// @param initialAdmin     Platform admin address (multisig recommended).
    /// @param initialRelayer   Convex backend relayer address.
    /// @param initialFeeBps    Platform fee in basis points (e.g., 250 = 2.5%).
    /// @param initialFeeRecipient Address to receive platform fees.
    /// @param acceptedStablecoins Array of ERC20 addresses to whitelist (USDT, USDC).
    constructor(
        address initialAdmin,
        address initialRelayer,
        uint256 initialFeeBps,
        address initialFeeRecipient,
        address[] memory acceptedStablecoins
    ) {
        if (initialAdmin == address(0) || initialRelayer == address(0)) {
            revert InvalidAddress();
        }
        if (initialFeeRecipient == address(0)) revert InvalidAddress();
        if (initialFeeBps > 5000) revert InvalidFee(initialFeeBps); // Max 50%

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);
        _grantRole(ARBITRATOR_ROLE, initialAdmin);
        _grantRole(RELAYER_ROLE, initialRelayer);

        _setRoleAdmin(RELAYER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ARBITRATOR_ROLE, ADMIN_ROLE);

        platformFeeBps = initialFeeBps;
        feeRecipient = initialFeeRecipient;

        // Native token (MATIC/ETH) is always accepted
        acceptedTokens[NATIVE_TOKEN] = true;

        for (uint256 i = 0; i < acceptedStablecoins.length;) {
            if (acceptedStablecoins[i] != address(0)) {
                acceptedTokens[acceptedStablecoins[i]] = true;
                emit TokenAcceptanceUpdated(acceptedStablecoins[i], true);
            }
            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //                       ESCROW CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Creates a new escrow and locks funds from the buyer.
    ///         For ERC20 tokens, the buyer must have approved this contract.
    ///         For native crypto, send the exact amount as msg.value.
    /// @param bookingId   Unique booking identifier from Convex backend.
    /// @param buyer       Address of the payer.
    /// @param seller      Address of the payee.
    /// @param token       ERC20 address, or address(0) for native crypto.
    /// @param amount      Total deposit amount (platform fee deducted on release).
    /// @param escrowType  Category of the escrow.
    /// @param duration    Escrow duration in seconds before expiry eligibility.
    /// @param convexId    Off-chain Convex document ID.
    function createEscrow(
        bytes32 bookingId,
        address buyer,
        address seller,
        address token,
        uint256 amount,
        EscrowType escrowType,
        uint256 duration,
        string calldata convexId
    )
        external
        payable
        onlyRole(RELAYER_ROLE)
        whenNotPaused
        nonReentrant
    {
        // ── Validation ──────────────────────────────────────────────
        if (escrowExists[bookingId]) revert EscrowAlreadyExists(bookingId);
        if (buyer == address(0) || seller == address(0)) revert InvalidAddress();
        if (buyer == seller) revert BuyerCannotBeSeller();
        if (amount == 0) revert InvalidAmount();
        if (!acceptedTokens[token]) revert TokenNotAccepted(token);
        if (duration < MIN_ESCROW_DURATION || duration > MAX_ESCROW_DURATION) {
            revert InvalidDuration();
        }

        // ── Calculate platform fee ──────────────────────────────────
        uint256 fee = (amount * platformFeeBps) / 10_000;

        // ── Lock funds ──────────────────────────────────────────────
        if (token == NATIVE_TOKEN) {
            if (msg.value < amount) {
                revert InsufficientNativeValue(msg.value, amount);
            }
            // Refund excess native crypto sent
            if (msg.value > amount) {
                (bool refundOk,) = payable(msg.sender).call{value: msg.value - amount}("");
                if (!refundOk) revert TransferFailed();
            }
        } else {
            // Pull ERC20 from buyer (buyer must have approved this contract)
            IERC20(token).safeTransferFrom(buyer, address(this), amount);
        }

        // ── Store escrow record ─────────────────────────────────────
        uint64 ts = uint64(block.timestamp);
        uint64 expiry = uint64(block.timestamp + duration);

        _escrows[bookingId] = Escrow({
            bookingId: bookingId,
            buyer: buyer,
            seller: seller,
            token: token,
            amount: amount,
            platformFee: fee,
            escrowType: escrowType,
            status: EscrowStatus.FUNDED,
            createdAt: ts,
            expiresAt: expiry,
            convexId: convexId
        });

        escrowExists[bookingId] = true;
        totalLockedByToken[token] += amount;
        unchecked { ++totalEscrows; }

        emit EscrowCreated(
            bookingId,
            buyer,
            seller,
            token,
            amount,
            fee,
            escrowType,
            expiry,
            convexId
        );
    }

    /// @notice Releases escrowed funds to the seller, minus the platform fee.
    ///         Called after successful checkout, delivery verification, or
    ///         booking completion.
    /// @param bookingId The escrow to release.
    function releaseFunds(bytes32 bookingId)
        external
        onlyRole(RELAYER_ROLE)
        whenNotPaused
        nonReentrant
    {
        Escrow storage escrow = _getEscrow(bookingId);
        if (escrow.status != EscrowStatus.FUNDED) {
            revert InvalidStatus(escrow.status, EscrowStatus.FUNDED);
        }

        escrow.status = EscrowStatus.RELEASED;
        totalLockedByToken[escrow.token] -= escrow.amount;

        uint256 sellerPayout = escrow.amount - escrow.platformFee;

        // ── Transfer to seller ──────────────────────────────────────
        _transferFunds(escrow.token, escrow.seller, sellerPayout);

        // ── Transfer platform fee ───────────────────────────────────
        if (escrow.platformFee > 0) {
            _transferFunds(escrow.token, feeRecipient, escrow.platformFee);
        }

        emit FundsReleased(
            bookingId,
            escrow.seller,
            sellerPayout,
            escrow.platformFee
        );
    }

    /// @notice Refunds the full escrowed amount back to the buyer.
    ///         Used for cancellations before delivery/checkout.
    /// @param bookingId The escrow to refund.
    function refundBuyer(bytes32 bookingId)
        external
        onlyRole(RELAYER_ROLE)
        whenNotPaused
        nonReentrant
    {
        Escrow storage escrow = _getEscrow(bookingId);
        if (escrow.status != EscrowStatus.FUNDED) {
            revert InvalidStatus(escrow.status, EscrowStatus.FUNDED);
        }

        escrow.status = EscrowStatus.REFUNDED;
        totalLockedByToken[escrow.token] -= escrow.amount;

        _transferFunds(escrow.token, escrow.buyer, escrow.amount);

        emit BuyerRefunded(bookingId, escrow.buyer, escrow.amount);
    }

    // ═══════════════════════════════════════════════════════════════════
    //                       DISPUTE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Flags an escrow as disputed, freezing release/refund until
    ///         an arbitrator resolves it.
    /// @param bookingId The escrow to dispute.
    /// @param reason    Human-readable reason for the dispute.
    function openDispute(
        bytes32 bookingId,
        string calldata reason
    )
        external
        onlyRole(RELAYER_ROLE)
        whenNotPaused
    {
        Escrow storage escrow = _getEscrow(bookingId);
        if (escrow.status != EscrowStatus.FUNDED) {
            revert InvalidStatus(escrow.status, EscrowStatus.FUNDED);
        }

        escrow.status = EscrowStatus.DISPUTED;

        emit EscrowDisputed(bookingId, msg.sender, reason);
    }

    /// @notice Resolves a dispute by splitting funds between buyer and seller.
    ///         The arbitrator decides the split. Platform fee is still deducted.
    /// @param bookingId       The disputed escrow.
    /// @param buyerRefundBps  Basis points of the total to refund to buyer (0–10000).
    function resolveDispute(
        bytes32 bookingId,
        uint256 buyerRefundBps
    )
        external
        onlyRole(ARBITRATOR_ROLE)
        whenNotPaused
        nonReentrant
    {
        Escrow storage escrow = _getEscrow(bookingId);
        if (escrow.status != EscrowStatus.DISPUTED) {
            revert InvalidStatus(escrow.status, EscrowStatus.DISPUTED);
        }
        if (buyerRefundBps > 10_000) revert InvalidFee(buyerRefundBps);

        escrow.status = EscrowStatus.RELEASED;
        totalLockedByToken[escrow.token] -= escrow.amount;

        uint256 afterFee = escrow.amount - escrow.platformFee;
        uint256 buyerRefund = (afterFee * buyerRefundBps) / 10_000;
        uint256 sellerPayout = afterFee - buyerRefund;

        // ── Distribute funds ────────────────────────────────────────
        if (buyerRefund > 0) {
            _transferFunds(escrow.token, escrow.buyer, buyerRefund);
        }
        if (sellerPayout > 0) {
            _transferFunds(escrow.token, escrow.seller, sellerPayout);
        }
        if (escrow.platformFee > 0) {
            _transferFunds(escrow.token, feeRecipient, escrow.platformFee);
        }

        emit DisputeResolved(
            bookingId,
            msg.sender,
            buyerRefundBps < 10_000,
            buyerRefund,
            sellerPayout
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //                       EXPIRY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Refunds an expired escrow back to the buyer. Can be called
    ///         by anyone after the expiry deadline to enable permissionless
    ///         recovery of stuck funds.
    /// @param bookingId The expired escrow to refund.
    function refundExpired(bytes32 bookingId)
        external
        whenNotPaused
        nonReentrant
    {
        Escrow storage escrow = _getEscrow(bookingId);
        if (escrow.status != EscrowStatus.FUNDED) {
            revert InvalidStatus(escrow.status, EscrowStatus.FUNDED);
        }
        if (block.timestamp < escrow.expiresAt) {
            revert EscrowNotExpired(bookingId);
        }

        escrow.status = EscrowStatus.EXPIRED;
        totalLockedByToken[escrow.token] -= escrow.amount;

        _transferFunds(escrow.token, escrow.buyer, escrow.amount);

        emit BuyerRefunded(bookingId, escrow.buyer, escrow.amount);
    }

    // ═══════════════════════════════════════════════════════════════════
    //                         READ FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Returns the full escrow record for a booking ID.
    /// @param bookingId The escrow to look up.
    /// @return escrow The stored Escrow struct.
    function getEscrow(bytes32 bookingId)
        external
        view
        returns (Escrow memory escrow)
    {
        return _escrows[bookingId];
    }

    /// @notice Returns the current status of an escrow.
    /// @param bookingId The escrow to check.
    /// @return status The current EscrowStatus.
    function getEscrowStatus(bytes32 bookingId)
        external
        view
        returns (EscrowStatus status)
    {
        return _escrows[bookingId].status;
    }

    /// @notice Checks if an escrow has passed its expiry deadline.
    /// @param bookingId The escrow to check.
    /// @return expired True if block.timestamp >= expiresAt.
    function isExpired(bytes32 bookingId)
        external
        view
        returns (bool expired)
    {
        return block.timestamp >= _escrows[bookingId].expiresAt;
    }

    // ═══════════════════════════════════════════════════════════════════
    //                        ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Updates the platform fee rate. Cannot exceed 50% (5000 bps).
    /// @param newFeeBps New fee rate in basis points.
    function setPlatformFee(uint256 newFeeBps)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (newFeeBps > 5000) revert InvalidFee(newFeeBps);
        uint256 oldFee = platformFeeBps;
        platformFeeBps = newFeeBps;
        emit PlatformFeeUpdated(oldFee, newFeeBps);
    }

    /// @notice Updates the address that receives platform fees.
    /// @param newRecipient New fee recipient address.
    function setFeeRecipient(address newRecipient)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (newRecipient == address(0)) revert InvalidAddress();
        feeRecipient = newRecipient;
    }

    /// @notice Adds or removes an ERC20 token from the accepted list.
    /// @param token    ERC20 address to update.
    /// @param accepted Whether the token should be accepted.
    function setTokenAcceptance(address token, bool accepted)
        external
        onlyRole(ADMIN_ROLE)
    {
        acceptedTokens[token] = accepted;
        emit TokenAcceptanceUpdated(token, accepted);
    }

    /// @notice Pauses all state-changing functions. Emergency circuit breaker.
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Resumes operations after emergency pause.
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ═══════════════════════════════════════════════════════════════════
    //                       INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════

    /// @dev Fetches an escrow by booking ID. Reverts if it doesn't exist.
    function _getEscrow(bytes32 bookingId)
        internal
        view
        returns (Escrow storage)
    {
        if (!escrowExists[bookingId]) revert EscrowNotFound(bookingId);
        return _escrows[bookingId];
    }

    /// @dev Transfers funds (native or ERC20) to a recipient.
    ///      Uses SafeERC20 for ERC20 to handle non-standard tokens (USDT).
    function _transferFunds(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        if (token == NATIVE_TOKEN) {
            (bool success,) = payable(recipient).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    /// @dev Allows contract to receive native crypto for escrow funding.
    receive() external payable {}
}

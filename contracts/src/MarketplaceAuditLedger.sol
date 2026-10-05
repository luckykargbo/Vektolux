// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title MarketplaceAuditLedger
 * @author Vektolux Engineering
 * @notice Immutable on-chain audit trail for high-value marketplace transactions.
 *         Logs cryptographic hashes of verified property deeds, vehicle sales,
 *         and hourly guesthouse bookings. Write access is restricted to the
 *         Convex backend relayer wallet(s).
 * @dev Uses OpenZeppelin AccessControl for role-based permissioning and
 *      Pausable as a circuit breaker for emergency freeze scenarios.
 *
 *      DESIGN DECISIONS:
 *      - Only hashes are stored on-chain (not full data) to minimize gas costs.
 *      - Full transaction data lives in Convex; the hash proves immutability.
 *      - Events are the primary data retrieval mechanism (via subgraph or logs).
 *      - A mapping provides O(1) existence checks for duplicate prevention.
 */
contract MarketplaceAuditLedger is AccessControl, Pausable {
    // ═══════════════════════════════════════════════════════════════════
    //                          CONSTANTS & ROLES
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Role granted to the Convex backend relayer wallet(s) authorized
    ///         to log transactions on-chain.
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    /// @notice Role for platform administrators who can pause/unpause and
    ///         manage relayer addresses.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ═══════════════════════════════════════════════════════════════════
    //                              ENUMS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Categories of marketplace transactions that can be logged.
    enum DealType {
        PROPERTY_SALE,           // 0 — Real estate sale
        PROPERTY_LONG_TERM_RENT, // 1 — Long-term rental agreement
        HOURLY_GUESTHOUSE,       // 2 — Hourly guesthouse booking
        VEHICLE_SALE,            // 3 — Car/truck/bike sale
        VEHICLE_RENTAL,          // 4 — Vehicle rental agreement
        RIDE_HAILING             // 5 — Completed ride-hailing trip
    }

    // ═══════════════════════════════════════════════════════════════════
    //                             STRUCTS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice On-chain record for a logged transaction.
    /// @param dealHash  Keccak256 hash of the full transaction payload.
    /// @param buyer     Address of the buyer / renter / passenger.
    /// @param seller    Address of the seller / property owner / driver.
    /// @param dealType  Category of the marketplace transaction.
    /// @param timestamp Block timestamp when the log was recorded.
    /// @param convexId  Off-chain Convex document ID for cross-reference.
    struct AuditRecord {
        bytes32 dealHash;
        address buyer;
        address seller;
        DealType dealType;
        uint64 timestamp;
        string convexId;
    }

    // ═══════════════════════════════════════════════════════════════════
    //                              STORAGE
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Maps a deal hash to its on-chain audit record.
    ///         Used for O(1) existence checks and duplicate prevention.
    mapping(bytes32 => AuditRecord) private _records;

    /// @notice Tracks whether a specific deal hash has been logged.
    mapping(bytes32 => bool) public isLogged;

    /// @notice Running counter of total transactions logged.
    uint256 public totalLogged;

    // ═══════════════════════════════════════════════════════════════════
    //                              EVENTS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Emitted when a high-value transaction is permanently logged.
    /// @param dealHash  Keccak256 hash of the deal payload (indexed for filtering).
    /// @param buyer     Buyer / renter / passenger address (indexed).
    /// @param seller    Seller / owner / driver address (indexed).
    /// @param dealType  Category of the transaction.
    /// @param timestamp Block timestamp of the log entry.
    /// @param convexId  Off-chain Convex document ID.
    event TransactionLogged(
        bytes32 indexed dealHash,
        address indexed buyer,
        address indexed seller,
        DealType dealType,
        uint256 timestamp,
        string convexId
    );

    /// @notice Emitted when a batch of transactions is logged in one call.
    /// @param count     Number of transactions logged in the batch.
    /// @param relayer   Address of the relayer that submitted the batch.
    event BatchLogged(uint256 count, address indexed relayer);

    // ═══════════════════════════════════════════════════════════════════
    //                              ERRORS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Thrown when attempting to log a deal hash that already exists.
    /// @param dealHash The duplicate hash.
    error DealAlreadyLogged(bytes32 dealHash);

    /// @notice Thrown when the deal hash is the zero value.
    error InvalidDealHash();

    /// @notice Thrown when buyer or seller is the zero address.
    error InvalidAddress();

    /// @notice Thrown when a batch array is empty or exceeds the limit.
    /// @param provided Number of items provided.
    /// @param maximum  Maximum allowed batch size.
    error InvalidBatchSize(uint256 provided, uint256 maximum);

    // ═══════════════════════════════════════════════════════════════════
    //                           CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Initializes the contract with the deployer as DEFAULT_ADMIN
    ///         and grants ADMIN_ROLE and RELAYER_ROLE to the initial relayer.
    /// @param initialAdmin   Address of the platform admin (multisig recommended).
    /// @param initialRelayer Address of the Convex backend relayer wallet.
    constructor(address initialAdmin, address initialRelayer) {
        if (initialAdmin == address(0) || initialRelayer == address(0)) {
            revert InvalidAddress();
        }

        // DEFAULT_ADMIN_ROLE can grant/revoke all other roles
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);
        _grantRole(RELAYER_ROLE, initialRelayer);

        // ADMIN_ROLE manages RELAYER_ROLE assignments
        _setRoleAdmin(RELAYER_ROLE, ADMIN_ROLE);
    }

    // ═══════════════════════════════════════════════════════════════════
    //                        CORE WRITE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Logs a single verified transaction hash on-chain.
    /// @dev Only callable by addresses holding RELAYER_ROLE. Reverts on
    ///      duplicate hashes to guarantee uniqueness.
    /// @param dealHash  Keccak256 hash of the full transaction payload.
    /// @param buyer     Address of the buyer / renter / passenger.
    /// @param seller    Address of the seller / owner / driver.
    /// @param dealType  Category of the marketplace transaction.
    /// @param convexId  Off-chain Convex document ID for cross-referencing.
    function logTransaction(
        bytes32 dealHash,
        address buyer,
        address seller,
        DealType dealType,
        string calldata convexId
    )
        external
        onlyRole(RELAYER_ROLE)
        whenNotPaused
    {
        _logTransaction(dealHash, buyer, seller, dealType, convexId);
    }

    /// @notice Logs a batch of transactions in a single call to save gas.
    /// @dev Maximum batch size is 50 to prevent block gas limit issues.
    ///      Each entry is validated independently; the entire batch reverts
    ///      if any single entry is invalid.
    /// @param dealHashes Array of keccak256 deal hashes.
    /// @param buyers     Array of buyer addresses.
    /// @param sellers    Array of seller addresses.
    /// @param dealTypes  Array of deal type categories.
    /// @param convexIds  Array of Convex document IDs.
    function logTransactionBatch(
        bytes32[] calldata dealHashes,
        address[] calldata buyers,
        address[] calldata sellers,
        DealType[] calldata dealTypes,
        string[] calldata convexIds
    )
        external
        onlyRole(RELAYER_ROLE)
        whenNotPaused
    {
        uint256 len = dealHashes.length;
        if (len == 0 || len > 50) {
            revert InvalidBatchSize(len, 50);
        }
        if (
            len != buyers.length ||
            len != sellers.length ||
            len != dealTypes.length ||
            len != convexIds.length
        ) {
            revert InvalidBatchSize(len, 50);
        }

        for (uint256 i = 0; i < len;) {
            _logTransaction(
                dealHashes[i],
                buyers[i],
                sellers[i],
                dealTypes[i],
                convexIds[i]
            );
            unchecked { ++i; }
        }

        emit BatchLogged(len, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════
    //                         READ FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Retrieves the full audit record for a given deal hash.
    /// @param dealHash The deal hash to look up.
    /// @return record The stored AuditRecord struct.
    function getRecord(bytes32 dealHash)
        external
        view
        returns (AuditRecord memory record)
    {
        return _records[dealHash];
    }

    /// @notice Verifies whether a specific deal hash has been logged on-chain.
    /// @param dealHash The deal hash to verify.
    /// @return exists True if the hash has been logged.
    function verifyTransaction(bytes32 dealHash)
        external
        view
        returns (bool exists)
    {
        return isLogged[dealHash];
    }

    // ═══════════════════════════════════════════════════════════════════
    //                        ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Pauses all write operations. Emergency circuit breaker.
    /// @dev Only callable by ADMIN_ROLE holders.
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Resumes write operations after an emergency pause.
    /// @dev Only callable by ADMIN_ROLE holders.
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ═══════════════════════════════════════════════════════════════════
    //                       INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════

    /// @dev Core logging logic shared by single and batch operations.
    /// @param dealHash  Keccak256 hash of the deal payload.
    /// @param buyer     Buyer address.
    /// @param seller    Seller address.
    /// @param dealType  Deal category enum.
    /// @param convexId  Off-chain Convex document ID.
    function _logTransaction(
        bytes32 dealHash,
        address buyer,
        address seller,
        DealType dealType,
        string calldata convexId
    ) internal {
        if (dealHash == bytes32(0)) revert InvalidDealHash();
        if (buyer == address(0) || seller == address(0)) revert InvalidAddress();
        if (isLogged[dealHash]) revert DealAlreadyLogged(dealHash);

        uint64 ts = uint64(block.timestamp);

        _records[dealHash] = AuditRecord({
            dealHash: dealHash,
            buyer: buyer,
            seller: seller,
            dealType: dealType,
            timestamp: ts,
            convexId: convexId
        });

        isLogged[dealHash] = true;
        unchecked { ++totalLogged; }

        emit TransactionLogged(
            dealHash,
            buyer,
            seller,
            dealType,
            ts,
            convexId
        );
    }
}

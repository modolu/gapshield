// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ProtectionReceipt} from "./ProtectionReceipt.sol";
import {IReferenceOracle} from "./interfaces/IReferenceOracle.sol";
import {PremiumMath} from "./libraries/PremiumMath.sol";
import {PayoutMath} from "./libraries/PayoutMath.sol";

/// @title ProtectionPool
/// @notice Fully collateralized USDG underwriting pool selling fixed-price weekend gap protection.
/// @dev Accounting model (GAPSHIELD_PRODUCT_ARCHITECTURE.md §7, docs/PHASE0_DECISIONS.md §9):
/// - `totalAssets()` is internally tracked LP-owned capital (`_lpAssets`), never `balanceOf(this)`.
/// - Premium is escrowed in `pendingPremium` and is not LP-owned until successful settlement.
/// - Settled payouts awaiting claims sit in `claimablePayouts` (P7), never in LP-owned assets.
/// - `protocolFeesAccrued` is never LP-owned.
/// - `freeCollateral = totalAssets - reservedLiability`; worst-case payout is reserved atomically at purchase.
/// Epoch state machine: None -> Open -> CloseRecorded -> Settled, or Open|CloseRecorded -> Voided after the
/// settlement deadline. Settlement and void windows are disjoint (`< settlementDeadline` vs `>=`).
contract ProtectionPool is ERC4626, Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum EpochStatus {
        None,
        Open,
        CloseRecorded,
        Settled,
        Voided
    }

    struct Asset {
        bytes32 oracleFeedId;
        string symbol;
        uint8 priceDecimals;
        bool enabled;
    }

    /// @notice Immutable after `createEpoch`.
    struct EpochConfig {
        bytes32 assetId;
        address oracle;
        uint64 saleCutoff;
        uint64 closeWindowStart;
        uint64 closeWindowEnd;
        uint64 openWindowStart;
        uint64 openWindowEnd;
        uint64 settlementDeadline;
        uint16 triggerBps;
        uint16 maxCoverBps;
        uint16 premiumBps;
        uint16 protocolFeeBps;
        uint256 minNotional;
        uint256 maxNotional;
        uint256 maxAggregateLiability;
    }

    struct EpochState {
        uint256 soldNotional;
        uint256 soldLiability;
        uint256 premiumCollected;
        uint256 closePrice;
        uint256 openPrice;
        uint64 closeTime;
        uint64 openTime;
        uint16 gapBps;
        uint16 coveredBps;
        EpochStatus status;
        bytes32 closeEvidence;
        bytes32 openEvidence;
    }

    /// @notice Immutable at purchase except `claimed`. The claimant is `receipt.ownerOf(policyId)`.
    struct Policy {
        uint256 epochId;
        uint256 notional;
        uint256 premiumUSDG;
        uint256 maxPayout;
        bool claimed;
    }

    uint256 public constant BPS = 10_000;
    /// @notice One whole USDG (6 decimals). Notionals must be multiples of this.
    uint256 public constant USDG_UNIT = 1e6;
    uint8 private constant _USDG_DECIMALS = 6;
    uint8 private constant _SHARE_DECIMALS_OFFSET = 6;

    ProtectionReceipt public immutable receipt;
    uint16 public immutable utilizationCapBps;

    uint256 private _lpAssets;
    uint256 public reservedLiability;
    uint256 public pendingPremium;
    /// @notice Settled buyer money awaiting claims (P7). Not LP-owned, not fees, not escrow, not free collateral.
    uint256 public claimablePayouts;
    /// @notice Accrued only by successful settlement; never LP-owned. Withdrawable by the owner only.
    uint256 public protocolFeesAccrued;
    uint256 public activeEpochId;
    uint256 public nextEpochId = 1;
    uint256 public nextPolicyId = 1;
    address public settlementOperator;

    mapping(bytes32 assetId => Asset) private _assets;
    mapping(uint256 epochId => EpochConfig) private _epochConfigs;
    mapping(uint256 epochId => EpochState) private _epochStates;
    mapping(uint256 policyId => Policy) private _policies;

    event LiquidityDeposited(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);
    event LiquidityWithdrawn(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event AssetAdded(bytes32 indexed assetId, bytes32 oracleFeedId, string symbol, uint8 priceDecimals);
    event AssetEnabledSet(bytes32 indexed assetId, bool enabled);
    event EpochCreated(uint256 indexed epochId, bytes32 indexed assetId, address indexed oracle, EpochConfig config);
    event ProtectionPurchased(
        uint256 indexed policyId,
        uint256 indexed epochId,
        address indexed buyer,
        uint256 notional,
        uint256 premium,
        uint256 maxPayout
    );
    event SettlementOperatorSet(address indexed previousOperator, address indexed newOperator);
    event CloseSettled(uint256 indexed epochId, uint256 price, uint64 referenceTime, bytes32 evidence);
    event OpenSettled(uint256 indexed epochId, uint256 price, uint64 referenceTime, bytes32 evidence);
    event EpochSettled(
        uint256 indexed epochId,
        uint16 gapBps,
        uint16 coveredBps,
        uint256 actualOwed,
        uint256 protocolFee,
        uint256 lpPremium
    );
    event EpochVoided(uint256 indexed epochId, uint256 releasedLiability, uint256 refundablePremium);
    event ProtectionClaimed(
        uint256 indexed policyId, uint256 indexed epochId, address indexed claimant, uint256 payout
    );
    event PremiumRefunded(uint256 indexed policyId, uint256 indexed epochId, address indexed claimant, uint256 amount);
    event ProtocolFeesWithdrawn(address indexed to, uint256 amount);

    error UnsupportedAssetDecimals(uint8 decimals);
    error ZeroAddress();
    error InvalidUtilizationCap(uint16 utilizationCapBps);
    error OwnershipCannotBeRenounced();
    error InvalidAsset();
    error AssetAlreadyExists(bytes32 assetId);
    error UnknownAsset(bytes32 assetId);
    error AssetDisabled(bytes32 assetId);
    error InvalidOracle(address oracle);
    error InvalidEpochTimes();
    error InvalidEpochEconomics();
    error InvalidNotionalBounds();
    error EpochAlreadyActive(uint256 epochId);
    error InvalidEpoch(uint256 epochId);
    error SaleClosed(uint256 epochId);
    error NotionalOutOfRange(uint256 notional, uint256 minNotional, uint256 maxNotional);
    error NotionalNotWholeUSDG(uint256 notional);
    error PoolCapacityExceeded(uint256 requestedReserve, uint256 capacity);
    error EpochCapacityExceeded(uint256 requestedLiability, uint256 maxAggregateLiability);
    error WithdrawalExceedsFreeCollateral(uint256 assets, uint256 freeCollateral);
    error UnknownPolicy(uint256 policyId);
    error NotSettlementOperator(address caller);
    error InvalidEpochStatus(uint256 epochId, EpochStatus status);
    error SettlementDeadlinePassed(uint256 epochId, uint64 settlementDeadline);
    error SettlementDeadlineNotReached(uint256 epochId, uint64 settlementDeadline);
    error InvalidReferencePrice();
    error InvalidReferenceTime(uint64 referenceTime, uint64 windowStart, uint64 windowEnd);
    error NotPolicyOwner(uint256 policyId, address caller);
    error PolicyAlreadyClaimed(uint256 policyId);
    error InsufficientProtocolFees(uint256 requested, uint256 available);

    constructor(IERC20Metadata usdg_, address owner_, uint16 utilizationCapBps_)
        ERC20("GapShield USDG Underwriter Share", "gsUSDG")
        ERC4626(usdg_)
        Ownable(owner_)
    {
        uint8 usdgDecimals = usdg_.decimals();
        if (usdgDecimals != _USDG_DECIMALS) revert UnsupportedAssetDecimals(usdgDecimals);
        if (utilizationCapBps_ == 0 || utilizationCapBps_ > BPS) revert InvalidUtilizationCap(utilizationCapBps_);
        utilizationCapBps = utilizationCapBps_;
        receipt = new ProtectionReceipt(address(this));
    }

    // ---------------------------------------------------------------------
    // Administration
    // ---------------------------------------------------------------------

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Not pause-gated so a compromised operator can be rotated during an incident.
    function setSettlementOperator(address newOperator) external onlyOwner {
        if (newOperator == address(0)) revert ZeroAddress();
        emit SettlementOperatorSet(settlementOperator, newOperator);
        settlementOperator = newOperator;
    }

    /// @notice Asset terms are immutable once added, so an epoch's bound feed can never change underneath it.
    function addAsset(bytes32 assetId, bytes32 oracleFeedId, string calldata symbol, uint8 priceDecimals)
        external
        onlyOwner
        whenNotPaused
    {
        if (assetId == bytes32(0) || oracleFeedId == bytes32(0) || bytes(symbol).length == 0) {
            revert InvalidAsset();
        }
        if (_assets[assetId].oracleFeedId != bytes32(0)) revert AssetAlreadyExists(assetId);
        _assets[assetId] =
            Asset({oracleFeedId: oracleFeedId, symbol: symbol, priceDecimals: priceDecimals, enabled: true});
        emit AssetAdded(assetId, oracleFeedId, symbol, priceDecimals);
    }

    /// @notice Enabling only gates `createEpoch`; it never affects an existing epoch.
    function setAssetEnabled(bytes32 assetId, bool enabled) external onlyOwner whenNotPaused {
        if (_assets[assetId].oracleFeedId == bytes32(0)) revert UnknownAsset(assetId);
        _assets[assetId].enabled = enabled;
        emit AssetEnabledSet(assetId, enabled);
    }

    /// @dev Ownerless operation would strand protocol fees and epoch creation; renouncing is disabled.
    function renounceOwnership() public view override onlyOwner {
        revert OwnershipCannotBeRenounced();
    }

    // ---------------------------------------------------------------------
    // Epochs
    // ---------------------------------------------------------------------

    function createEpoch(EpochConfig calldata config) external onlyOwner whenNotPaused returns (uint256 epochId) {
        uint256 currentId = activeEpochId;
        if (_isEpochActive(currentId)) revert EpochAlreadyActive(currentId);

        Asset storage asset_ = _assets[config.assetId];
        if (asset_.oracleFeedId == bytes32(0)) revert UnknownAsset(config.assetId);
        if (!asset_.enabled) revert AssetDisabled(config.assetId);
        if (config.oracle.code.length == 0) revert InvalidOracle(config.oracle);

        if (
            config.saleCutoff <= block.timestamp || config.closeWindowStart < config.saleCutoff
                || config.closeWindowEnd <= config.closeWindowStart || config.openWindowStart < config.closeWindowEnd
                || config.openWindowEnd <= config.openWindowStart || config.settlementDeadline <= config.openWindowEnd
        ) revert InvalidEpochTimes();

        if (
            config.maxCoverBps == 0 || uint256(config.triggerBps) + config.maxCoverBps > BPS || config.premiumBps == 0
                || config.premiumBps > config.maxCoverBps || config.protocolFeeBps > BPS
                || config.maxAggregateLiability == 0
        ) revert InvalidEpochEconomics();

        if (
            config.minNotional == 0 || config.maxNotional < config.minNotional || config.minNotional % USDG_UNIT != 0
                || config.maxNotional % USDG_UNIT != 0
        ) revert InvalidNotionalBounds();

        epochId = nextEpochId++;
        _epochConfigs[epochId] = config;
        _epochStates[epochId].status = EpochStatus.Open;
        activeEpochId = epochId;

        emit EpochCreated(epochId, config.assetId, config.oracle, config);
    }

    // ---------------------------------------------------------------------
    // Protection purchase
    // ---------------------------------------------------------------------

    /// @notice Buys protection for a whole-USDG `notional`. Reserves the worst-case payout atomically.
    function buyProtection(uint256 epochId, uint256 notional)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 policyId)
    {
        EpochState storage state = _epochStates[epochId];
        if (epochId != activeEpochId || state.status != EpochStatus.Open) revert InvalidEpoch(epochId);

        EpochConfig storage config = _epochConfigs[epochId];
        if (block.timestamp >= config.saleCutoff) revert SaleClosed(epochId);
        if (notional < config.minNotional || notional > config.maxNotional) {
            revert NotionalOutOfRange(notional, config.minNotional, config.maxNotional);
        }
        if (notional % USDG_UNIT != 0) revert NotionalNotWholeUSDG(notional);

        uint256 premium = PremiumMath.premium(notional, config.premiumBps);
        uint256 maxPayout = PayoutMath.maxPayout(notional, config.maxCoverBps);

        uint256 newReserved = reservedLiability + maxPayout;
        uint256 capacity = Math.mulDiv(_lpAssets, utilizationCapBps, BPS);
        if (newReserved > capacity) revert PoolCapacityExceeded(newReserved, capacity);

        uint256 newSoldLiability = state.soldLiability + maxPayout;
        if (newSoldLiability > config.maxAggregateLiability) {
            revert EpochCapacityExceeded(newSoldLiability, config.maxAggregateLiability);
        }

        // Effects
        reservedLiability = newReserved;
        pendingPremium += premium;
        state.soldNotional += notional;
        state.soldLiability = newSoldLiability;
        state.premiumCollected += premium;

        policyId = nextPolicyId++;
        _policies[policyId] =
            Policy({epochId: epochId, notional: notional, premiumUSDG: premium, maxPayout: maxPayout, claimed: false});

        emit ProtectionPurchased(policyId, epochId, msg.sender, notional, premium, maxPayout);

        // Interactions
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), premium);
        receipt.mint(msg.sender, policyId);
    }

    // ---------------------------------------------------------------------
    // Settlement (operator-gated; never pause-gated)
    // ---------------------------------------------------------------------

    /// @notice Records the epoch's close reference through its frozen oracle. Open -> CloseRecorded.
    /// @dev `payable` so vendor verification fees (e.g. Pyth) can be forwarded; fee-less adapters reject value.
    function settleClose(uint256 epochId, bytes calldata updateData) external payable nonReentrant {
        EpochState storage state = _beginSettlement(epochId, EpochStatus.Open);
        EpochConfig storage config = _epochConfigs[epochId];

        (uint256 price, uint64 referenceTime, bytes32 evidence) =
            _verifyReference(config, config.closeWindowStart, config.closeWindowEnd, updateData);

        state.closePrice = price;
        state.closeTime = referenceTime;
        state.closeEvidence = evidence;
        state.status = EpochStatus.CloseRecorded;
        emit CloseSettled(epochId, price, referenceTime, evidence);
    }

    /// @notice Records the epoch's open reference and finalizes the epoch. CloseRecorded -> Settled.
    function settleOpen(uint256 epochId, bytes calldata updateData) external payable nonReentrant {
        EpochState storage state = _beginSettlement(epochId, EpochStatus.CloseRecorded);
        EpochConfig storage config = _epochConfigs[epochId];

        (uint256 price, uint64 referenceTime, bytes32 evidence) =
            _verifyReference(config, config.openWindowStart, config.openWindowEnd, updateData);

        state.openPrice = price;
        state.openTime = referenceTime;
        state.openEvidence = evidence;
        emit OpenSettled(epochId, price, referenceTime, evidence);

        _finalizeSettlement(epochId, config, state);
    }

    /// @notice Permissionless, deterministic void once the settlement deadline has passed without settlement.
    /// Releases the epoch's whole reserve; its premium stays escrowed for per-policy refunds via `claim`.
    function voidEpoch(uint256 epochId) external {
        EpochState storage state = _epochStates[epochId];
        if (state.status != EpochStatus.Open && state.status != EpochStatus.CloseRecorded) {
            revert InvalidEpochStatus(epochId, state.status);
        }
        uint64 deadline = _epochConfigs[epochId].settlementDeadline;
        if (block.timestamp < deadline) revert SettlementDeadlineNotReached(epochId, deadline);

        reservedLiability -= state.soldLiability;
        state.status = EpochStatus.Voided;
        emit EpochVoided(epochId, state.soldLiability, state.premiumCollected);
    }

    // ---------------------------------------------------------------------
    // Claims and refunds (never pause-gated)
    // ---------------------------------------------------------------------

    /// @notice One-time finalization of a policy by its receipt owner: the settled payout (possibly zero) for a
    /// Settled epoch, or the full premium refund for a Voided epoch.
    function claim(uint256 policyId) external nonReentrant returns (uint256 amount) {
        Policy storage policy = _policies[policyId];
        uint256 epochId = policy.epochId;
        if (epochId == 0) revert UnknownPolicy(policyId);
        if (receipt.ownerOf(policyId) != msg.sender) revert NotPolicyOwner(policyId, msg.sender);
        if (policy.claimed) revert PolicyAlreadyClaimed(policyId);

        EpochState storage state = _epochStates[epochId];
        if (state.status == EpochStatus.Settled) {
            amount = PayoutMath.payout(policy.notional, state.coveredBps);
            policy.claimed = true;
            claimablePayouts -= amount;
            emit ProtectionClaimed(policyId, epochId, msg.sender, amount);
        } else if (state.status == EpochStatus.Voided) {
            amount = policy.premiumUSDG;
            policy.claimed = true;
            pendingPremium -= amount;
            emit PremiumRefunded(policyId, epochId, msg.sender, amount);
        } else {
            revert InvalidEpochStatus(epochId, state.status);
        }

        if (amount > 0) IERC20(asset()).safeTransfer(msg.sender, amount);
    }

    // ---------------------------------------------------------------------
    // Protocol fees (owner; accrued fees only)
    // ---------------------------------------------------------------------

    /// @notice Withdraws only `protocolFeesAccrued`. There is no general token sweep.
    function withdrawProtocolFees(address to, uint256 amount) external nonReentrant onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        uint256 available = protocolFeesAccrued;
        if (amount > available) revert InsufficientProtocolFees(amount, available);
        protocolFeesAccrued = available - amount;
        emit ProtocolFeesWithdrawn(to, amount);
        IERC20(asset()).safeTransfer(to, amount);
    }

    // ---------------------------------------------------------------------
    // ERC-4626 vault: LP-owned capital only
    // ---------------------------------------------------------------------

    /// @notice LP-owned capital. Excludes escrowed premium, settled claimable payouts and protocol fees;
    /// ignores direct token donations.
    function totalAssets() public view override returns (uint256) {
        return _lpAssets;
    }

    /// @notice Capital not backing any reserved liability.
    function freeCollateral() public view returns (uint256) {
        return _lpAssets - reservedLiability;
    }

    function maxDeposit(address) public view override returns (uint256) {
        return _depositsOpen() ? type(uint256).max : 0;
    }

    function maxMint(address) public view override returns (uint256) {
        return _depositsOpen() ? type(uint256).max : 0;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        if (_activeEpochPastCutoff()) return 0;
        return Math.min(_convertToAssets(balanceOf(owner), Math.Rounding.Floor), freeCollateral());
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        if (_activeEpochPastCutoff()) return 0;
        return Math.min(balanceOf(owner), _convertToShares(freeCollateral(), Math.Rounding.Floor));
    }

    function deposit(uint256 assets, address receiver) public override nonReentrant whenNotPaused returns (uint256) {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override nonReentrant whenNotPaused returns (uint256) {
        return super.mint(shares, receiver);
    }

    /// @notice Not pause-gated: genuinely free collateral is always withdrawable outside the post-cutoff lock.
    function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256) {
        return super.withdraw(assets, receiver, owner);
    }

    /// @notice Not pause-gated: genuinely free collateral is always withdrawable outside the post-cutoff lock.
    function redeem(uint256 shares, address receiver, address owner) public override nonReentrant returns (uint256) {
        return super.redeem(shares, receiver, owner);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        _lpAssets += assets;
        emit LiquidityDeposited(caller, receiver, assets, shares);
        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        // Defence in depth, consistent with the max* views: nothing is withdrawable while locked,
        // otherwise at most the free collateral (a zero amount is always a no-op).
        uint256 withdrawable = _activeEpochPastCutoff() ? 0 : freeCollateral();
        if (assets > withdrawable) revert WithdrawalExceedsFreeCollateral(assets, withdrawable);
        _lpAssets -= assets;
        emit LiquidityWithdrawn(caller, receiver, owner, assets, shares);
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return _SHARE_DECIMALS_OFFSET;
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function getAsset(bytes32 assetId) external view returns (Asset memory) {
        return _assets[assetId];
    }

    function getEpochConfig(uint256 epochId) external view returns (EpochConfig memory) {
        return _epochConfigs[epochId];
    }

    function getEpochState(uint256 epochId) external view returns (EpochState memory) {
        return _epochStates[epochId];
    }

    function getPolicy(uint256 policyId) external view returns (Policy memory) {
        return _policies[policyId];
    }

    /// @notice Premium and worst-case payout for `notional` under an epoch's terms. Does not check sale state.
    function quote(uint256 epochId, uint256 notional) external view returns (uint256 premium, uint256 maxPayout) {
        EpochConfig storage config = _epochConfigs[epochId];
        if (_epochStates[epochId].status == EpochStatus.None) revert InvalidEpoch(epochId);
        premium = PremiumMath.premium(notional, config.premiumBps);
        maxPayout = PayoutMath.maxPayout(notional, config.maxCoverBps);
    }

    /// @notice Settled payout of a policy (0 unless its epoch is Settled). Informational; ignores `claimed`.
    function previewPayout(uint256 policyId) external view returns (uint256) {
        Policy storage policy = _policies[policyId];
        if (policy.epochId == 0) revert UnknownPolicy(policyId);
        EpochState storage state = _epochStates[policy.epochId];
        if (state.status != EpochStatus.Settled) return 0;
        return PayoutMath.payout(policy.notional, state.coveredBps);
    }

    /// @notice Hypothetical payout of an existing policy for given close/open reference prices (payout scrubber).
    function previewPayoutAt(uint256 policyId, uint256 closePrice, uint256 openPrice) external view returns (uint256) {
        Policy storage policy = _policies[policyId];
        if (policy.epochId == 0) revert UnknownPolicy(policyId);
        EpochConfig storage config = _epochConfigs[policy.epochId];
        return PayoutMath.payoutFor(policy.notional, closePrice, openPrice, config.triggerBps, config.maxCoverBps);
    }

    // ---------------------------------------------------------------------
    // Settlement internals
    // ---------------------------------------------------------------------

    function _beginSettlement(uint256 epochId, EpochStatus expected) internal view returns (EpochState storage state) {
        if (msg.sender != settlementOperator) revert NotSettlementOperator(msg.sender);
        state = _epochStates[epochId];
        if (state.status != expected) revert InvalidEpochStatus(epochId, state.status);
        uint64 deadline = _epochConfigs[epochId].settlementDeadline;
        if (block.timestamp >= deadline) revert SettlementDeadlinePassed(epochId, deadline);
    }

    /// @dev Calls the epoch's frozen oracle, then re-checks the critical conditions itself: positive price,
    /// reference time inside `[windowStart, windowEnd)` and not in the future.
    function _verifyReference(
        EpochConfig storage config,
        uint64 windowStart,
        uint64 windowEnd,
        bytes calldata updateData
    ) internal returns (uint256 price, uint64 referenceTime, bytes32 evidence) {
        bytes32 feedId = _assets[config.assetId].oracleFeedId;
        (price, referenceTime, evidence) = IReferenceOracle(config.oracle).verifyReference{value: msg.value}(
            feedId, windowStart, windowEnd, updateData
        );
        if (price == 0) revert InvalidReferencePrice();
        if (referenceTime < windowStart || referenceTime >= windowEnd || referenceTime > block.timestamp) {
            revert InvalidReferenceTime(referenceTime, windowStart, windowEnd);
        }
    }

    /// @dev P7 accounting. Immediately before this runs for the active epoch,
    /// `actualOwed <= soldLiability <= reservedLiability <= _lpAssets`, so no subtraction underflows.
    function _finalizeSettlement(uint256 epochId, EpochConfig storage config, EpochState storage state) internal {
        uint256 gap = PayoutMath.gapBps(state.closePrice, state.openPrice);
        uint256 covered = PayoutMath.coveredBps(gap, config.triggerBps, config.maxCoverBps);
        uint256 actualOwed = PayoutMath.payout(state.soldNotional, covered);

        reservedLiability -= state.soldLiability;
        _lpAssets -= actualOwed;
        claimablePayouts += actualOwed;

        uint256 premium = state.premiumCollected;
        pendingPremium -= premium;
        uint256 protocolFee = PremiumMath.protocolFee(premium, config.protocolFeeBps);
        protocolFeesAccrued += protocolFee;
        _lpAssets += premium - protocolFee;

        // gap <= 10_000 and covered <= maxCoverBps, so both fit in uint16.
        state.gapBps = uint16(gap);
        state.coveredBps = uint16(covered);
        state.status = EpochStatus.Settled;

        emit EpochSettled(epochId, uint16(gap), uint16(covered), actualOwed, protocolFee, premium - protocolFee);
    }

    // ---------------------------------------------------------------------
    // Internal state predicates
    // ---------------------------------------------------------------------

    function _isEpochActive(uint256 epochId) internal view returns (bool) {
        EpochStatus status = _epochStates[epochId].status;
        return status == EpochStatus.Open || status == EpochStatus.CloseRecorded;
    }

    /// @dev True from the active epoch's sale cutoff until it is settled or voided.
    function _activeEpochPastCutoff() internal view returns (bool) {
        uint256 epochId = activeEpochId;
        return _isEpochActive(epochId) && block.timestamp >= _epochConfigs[epochId].saleCutoff;
    }

    /// @dev Deposits close with policy sales and while paused.
    function _depositsOpen() internal view returns (bool) {
        return !paused() && !_activeEpochPastCutoff();
    }
}

// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { MathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

/// @title MerklAdapter
/// @author Merkl SAS
/// @notice An unopinionated ERC4626 wrapper around any other ERC4626 vault that skims a performance
/// fee (on interest) and a management fee (on assets over time) for a `feeRecipient`.
/// @dev Inspired by Morpho's VaultV2 fee accounting, stripped down to a single underlying vault and a
/// single fee recipient, with no allocation logic, gates, timelocks or interest-rate caps.
///
/// Fees are realized by minting adapter shares to `feeRecipient` whenever interest is accrued. Because
/// minting dilutes existing holders, a depositor's shares keep tracking their *fee-adjusted* claim on
/// the underlying vault.
///
/// In the extreme where `performanceFee == BASE_18` (100%), every unit of interest is captured: a user
/// who deposits 1 asset keeps a claim worth exactly 1 asset, while all yield earned in the meantime is
/// owned by `feeRecipient`.
contract MerklAdapter is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, ERC4626Upgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;

    /// @notice Base used for fee computations (1e18 == 100%).
    uint256 public constant BASE_18 = 1e18;

    /// @notice Number of seconds in a year, used to bound the per-second management fee rate.
    uint256 internal constant _SECONDS_PER_YEAR = 365 days;

    /// @notice Upper bound for the management fee, expressed as a per-second rate in `BASE_18`.
    /// @dev Equivalent to a ~100%/year linear management fee. Performance fees are not bounded below
    /// 100% so that the recipient can capture all of the interest.
    uint256 public constant MAX_MANAGEMENT_FEE = BASE_18 / _SECONDS_PER_YEAR;

    // =================================== STORAGE ===================================

    /// @notice The ERC4626 vault this adapter deposits its assets into.
    IERC4626Upgradeable public underlyingVault;

    /// @notice Performance fee charged on interest, in `BASE_18` (can be set up to 100%).
    uint256 public performanceFee;

    /// @notice Management fee charged on total assets, expressed as a per-second rate in `BASE_18`.
    uint256 public managementFee;

    /// @notice Recipient of both the performance and management fees.
    address public feeRecipient;

    /// @notice Total assets recorded at the last fee accrual, used to measure interest.
    uint256 public lastTotalAssets;

    /// @notice Timestamp of the last fee accrual, used to measure elapsed time for the management fee.
    uint256 public lastUpdate;

    // =================================== EVENTS ====================================

    event PerformanceFeeSet(uint256 performanceFee);
    event ManagementFeeSet(uint256 managementFee);
    event FeeRecipientSet(address indexed feeRecipient);
    event FeesAccrued(uint256 feeShares, uint256 newTotalAssets);

    // =================================== ERRORS ====================================

    error ZeroAddress();
    error InvalidAsset();
    error PerformanceFeeTooHigh();
    error ManagementFeeTooHigh();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // =============================== INITIALIZATION ================================

    /// @notice Initializes the adapter.
    /// @param name_ Name of the adapter share token.
    /// @param symbol_ Symbol of the adapter share token.
    /// @param _asset Asset managed by the adapter; must equal the underlying vault's asset.
    /// @param _underlyingVault ERC4626 vault assets are forwarded to.
    /// @param _performanceFee Performance fee on interest, in `BASE_18` (`BASE_18` == 100%).
    /// @param _managementFee Management fee, as a per-second rate in `BASE_18`.
    /// @param _feeRecipient Address receiving the fees.
    /// @param _owner Address allowed to update fees and the fee recipient.
    function initialize(
        string memory name_,
        string memory symbol_,
        IERC20Upgradeable _asset,
        IERC4626Upgradeable _underlyingVault,
        uint256 _performanceFee,
        uint256 _managementFee,
        address _feeRecipient,
        address _owner
    ) external initializer {
        if (address(_asset) == address(0) || address(_underlyingVault) == address(0) || _feeRecipient == address(0) || _owner == address(0))
            revert ZeroAddress();
        // The adapter and its underlying vault must share the exact same asset.
        if (_underlyingVault.asset() != address(_asset)) revert InvalidAsset();
        if (_performanceFee > BASE_18) revert PerformanceFeeTooHigh();
        if (_managementFee > MAX_MANAGEMENT_FEE) revert ManagementFeeTooHigh();

        __ERC4626_init(_asset);
        __ERC20_init(name_, symbol_);
        __Ownable_init();
        __ReentrancyGuard_init();
        _transferOwnership(_owner);

        underlyingVault = _underlyingVault;
        performanceFee = _performanceFee;
        managementFee = _managementFee;
        feeRecipient = _feeRecipient;
        lastUpdate = block.timestamp;

        emit PerformanceFeeSet(_performanceFee);
        emit ManagementFeeSet(_managementFee);
        emit FeeRecipientSet(_feeRecipient);
    }

    // =============================== ERC4626 LOGIC ================================

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Real assets recoverable from the underlying vault, plus any idle balance sitting on the
    /// adapter. This is the gross value: fees are accounted for through share dilution, not here.
    function totalAssets() public view override returns (uint256) {
        return underlyingVault.convertToAssets(underlyingVault.balanceOf(address(this))) + IERC20Upgradeable(asset()).balanceOf(address(this));
    }

    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256) {
        _accrueFee();
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256) {
        _accrueFee();
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256) {
        _accrueFee();
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public override nonReentrant returns (uint256) {
        _accrueFee();
        return super.redeem(shares, receiver, owner);
    }

    /// @dev Pulls `assets` from `caller` and forwards them to the underlying vault, then mints `shares`.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        IERC20Upgradeable assetToken = IERC20Upgradeable(asset());
        assetToken.safeTransferFrom(caller, address(this), assets);
        assetToken.forceApprove(address(underlyingVault), assets);
        underlyingVault.deposit(assets, address(this));

        _mint(receiver, shares);
        // Record the new principal so the freshly deposited assets are not later mistaken for interest.
        lastTotalAssets = totalAssets();

        emit Deposit(caller, receiver, assets, shares);
    }

    /// @dev Burns `shares` and withdraws `assets` from the underlying vault straight to `receiver`.
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal override {
        if (caller != owner) _spendAllowance(owner, caller, shares);
        _burn(owner, shares);

        underlyingVault.withdraw(assets, receiver, address(this));
        lastTotalAssets = totalAssets();

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    // ================================ FEE ACCRUAL =================================

    /// @notice Accrues both fees by minting the corresponding adapter shares to `feeRecipient`.
    /// @dev Performance fee is charged on the interest earned since the last accrual; management fee is
    /// charged on the current total assets pro-rated over the elapsed time. Fee shares are priced using
    /// the assets-net-of-fees so the resulting share value matches what is owed.
    function _accrueFee() internal {
        uint256 newTotalAssets = totalAssets();
        uint256 elapsed = block.timestamp - lastUpdate;

        uint256 feeAssets;
        if (newTotalAssets > lastTotalAssets && performanceFee != 0) {
            uint256 interest = newTotalAssets - lastTotalAssets;
            feeAssets = interest.mulDiv(performanceFee, BASE_18);
        }
        if (elapsed != 0 && managementFee != 0) {
            feeAssets += newTotalAssets.mulDiv(managementFee * elapsed, BASE_18);
        }
        // Fees can never exceed the assets actually under management.
        if (feeAssets > newTotalAssets) feeAssets = newTotalAssets;

        uint256 feeShares;
        if (feeAssets != 0) {
            uint256 assetsAfterFees = newTotalAssets - feeAssets;
            // Mirrors ERC4626 `_convertToShares` but against the post-fee asset base, so that the minted
            // shares are worth `feeAssets` once they dilute the existing supply.
            feeShares = feeAssets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), assetsAfterFees + 1, MathUpgradeable.Rounding.Down);
            if (feeShares != 0) _mint(feeRecipient, feeShares);
        }

        lastTotalAssets = newTotalAssets;
        lastUpdate = block.timestamp;

        emit FeesAccrued(feeShares, newTotalAssets);
    }

    // ================================= GOVERNANCE =================================

    /// @notice Updates the performance fee (capped at 100%). Accrues outstanding fees first.
    function setPerformanceFee(uint256 _performanceFee) external onlyOwner {
        if (_performanceFee > BASE_18) revert PerformanceFeeTooHigh();
        _accrueFee();
        performanceFee = _performanceFee;
        emit PerformanceFeeSet(_performanceFee);
    }

    /// @notice Updates the management fee (per-second rate). Accrues outstanding fees first.
    function setManagementFee(uint256 _managementFee) external onlyOwner {
        if (_managementFee > MAX_MANAGEMENT_FEE) revert ManagementFeeTooHigh();
        _accrueFee();
        managementFee = _managementFee;
        emit ManagementFeeSet(_managementFee);
    }

    /// @notice Updates the recipient of both fees. Accrues outstanding fees to the old recipient first.
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) revert ZeroAddress();
        _accrueFee();
        feeRecipient = _feeRecipient;
        emit FeeRecipientSet(_feeRecipient);
    }
}

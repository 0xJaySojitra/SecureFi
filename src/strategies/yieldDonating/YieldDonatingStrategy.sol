// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseHealthCheck} from "@octant-core/strategies/periphery/BaseHealthCheck.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ERC4626 interface for Spark Vault integration
interface IERC4626 {
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function maxDeposit(address receiver) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title YieldDonating Strategy Template
 * @author Octant
 * @notice Template for creating YieldDonating strategies that mint profits to donationAddress
 * @dev This strategy template works with the TokenizedStrategy pattern where
 *      initialization and management functions are handled by a separate contract.
 *      The strategy focuses on the core yield generation logic.
 *
 *      NOTE: To implement permissioned functions you can use the onlyManagement,
 *      onlyEmergencyAuthorized and onlyKeepers modifiers
 */
contract YieldDonatingStrategy is BaseHealthCheck {
    using SafeERC20 for IERC20;

    /// @notice Address of the ERC4626 vault (Spark Vault)
    IERC4626 public immutable YIELD_SOURCE;

    /**
     * @param _asset Address of the underlying asset
     * @param _name Strategy name
     * @param _management Address with management role
     * @param _keeper Address with keeper role
     * @param _emergencyAdmin Address with emergency admin role
     * @param _donationAddress Address that receives donated/minted yield
     * @param _enableBurning Whether loss-protection burning from donation address is enabled
     * @param _tokenizedStrategyAddress Address of TokenizedStrategy implementation
     */
    constructor(
        address _yieldSource,
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    )
        BaseHealthCheck(
            _asset,
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {
        YIELD_SOURCE = IERC4626(_yieldSource);

        // max allow Yield source to withdraw assets
        IERC20(_asset).forceApprove(_yieldSource, type(uint256).max);

        // TokenizedStrategy initialization will be handled separately
        // This is just a template - the actual initialization depends on
        // the specific TokenizedStrategy implementation being used
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Can deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy can attempt
     * to deploy.
     */
    function _deployFunds(uint256 _amount) internal override {
        // Deploy funds to the Spark ERC4626 vault
        if (_amount > 0) {
            // Deposit assets into the ERC4626 vault and receive shares
            // Note: Deposit limits are already checked by TokenizedStrategy via availableDepositLimit()
            YIELD_SOURCE.deposit(_amount, address(this));
        }
    }

    /**
     * @dev Should attempt to free the '_amount' of 'asset'.
     *
     * NOTE: The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        // Free funds from the Aave ERC4626 vault
        if (_amount > 0) {
            // Check how much we can withdraw
            uint256 maxWithdraw = YIELD_SOURCE.maxWithdraw(address(this));

            // Limit withdrawal to what's available
            uint256 amountToWithdraw = _amount > maxWithdraw ? maxWithdraw : _amount;

            if (amountToWithdraw > 0) {
                // Withdraw assets from the ERC4626 vault
                YIELD_SOURCE.withdraw(amountToWithdraw, address(this), address(this));
            }
        }
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // Calculate total assets held by the strategy

        // 1. Get idle assets (assets sitting in the strategy contract)
        uint256 idleAssets = IERC20(asset).balanceOf(address(this));

        // 2. Get assets deployed in the Spark ERC4626 vault
        uint256 sharesBalance = YIELD_SOURCE.balanceOf(address(this));
        uint256 deployedAssets = 0;

        if (sharesBalance > 0) {
            // Convert shares to underlying assets
            deployedAssets = YIELD_SOURCE.convertToAssets(sharesBalance);
        }

        // 3. Return total assets (idle + deployed)
        _totalAssets = idleAssets + deployedAssets;

        // Note: In a more complex implementation, you might also:
        // - Claim any additional rewards from the vault
        // - Compound rewards back into the vault
        // - Handle any yield that should be donated to the donation address
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Returns the maximum amount that can be withdrawn from the Spark vault.
     * @return The available amount that can be withdrawn.
     */
    function availableWithdrawLimit(address /*_owner*/) public view virtual override returns (uint256) {
        // Return the maximum amount the vault allows us to withdraw
        return IERC20(asset).balanceOf(address(this)) + YIELD_SOURCE.maxWithdraw(address(this));
    }

    /**
     * @notice Gets the max amount of `asset` that can be deposited.
     * @dev Returns the maximum amount that can be deposited into the Spark vault.
     * @return The available amount that can be deposited.
     */
    function availableDepositLimit(address /*_owner*/) public view virtual override returns (uint256) {
        // Return the maximum amount the vault allows us to deposit
        uint256 idleBalance = IERC20(asset).balanceOf(address(this));
        uint256 vaultLimit = YIELD_SOURCE.maxDeposit(address(this));
        return vaultLimit > idleBalance ? vaultLimit - idleBalance : 0;
    }

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a permissioned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed position maintenance or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * This will have no effect on PPS of the strategy till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     */
    function _tend(uint256 _totalIdle) internal virtual override {}

    /**
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     */
    function _tendTrigger() internal view virtual override returns (bool) {
        return false;
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     */
    function _emergencyWithdraw(uint256 _amount) internal virtual override {
        // Use _freeFunds which handles vault limits safely
        // This ensures we don't withdraw more than what's available
        _freeFunds(_amount);
    }
}

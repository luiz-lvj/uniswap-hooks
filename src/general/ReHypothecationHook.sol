// SPDX-License-Identifier: MIT
// OpenZeppelin Uniswap Hooks (last updated v1.2.0) (src/general/ReHypothecationHook.sol)

pragma solidity ^0.8.24;

// External imports
import {AbstractAssetVault} from "../utils/AbstractAssetVault.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Position} from "@uniswap/v4-core/src/libraries/Position.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
// Internal imports
import {BaseHook} from "../base/BaseHook.sol";
import {CurrencySettler} from "../utils/CurrencySettler.sol";
import {console} from "forge-std/console.sol";

/**
 * @dev A Uniswap V4 hook that enables rehypothecation of liquidity positions.
 *
 * This hook allows users to deposit assets into yield-generating sources (e.g., ERC-4626 vaults)
 * while still making the same capital available as swapping liquidity in Uniswap pools.
 * Assets earn yield in yield sources most of the time, and are temporarily surfaced as pool
 * liquidity through Just-in-Time (JIT) provisioning during incoming swaps.
 *
 * Conceptually, the hook acts as an intermediary that manages:
 * - the user-facing ERC20 share token (representing rehypothecated positions), and
 * - the underlying relationship between yield sources and pool liquidity.
 *
 * Key features:
 * - Users can deposit assets into yield sources via the hook and receive ERC20 shares
 *   that represent their rehypothecated liquidity position.
 * - The hook dynamically manages pool liquidity based on available yield source assets,
 *   performing JIT provisioning during swaps.
 * - After swaps, assets are deposited back into yield sources to continue earning yield.
 * - Supports both ERC20 tokens and native ETH (with proper integration).
 *
 * NOTE: By default, the hook liquidity position is placed in the entire curve range. Override
 * the `getTickLower` and `getTickUpper` functions to customize the position.
 *
 * NOTE: By default, both rehypothecated and cannonical liquidity modifications are allowed. Override
 *  `beforeAddLiquidity` and `beforeRemoveLiquidity` and revert to enforce rehypothecated liquidity modifications only.
 *
 * WARNING: This is experimental software and is provided on an "as is" and "as available" basis.
 * We do not give any warranties and will not be liable for any losses incurred through any use of
 * this code base.
 * _Available since v1.1.0_
 */
abstract contract ReHypothecationHook is BaseHook, AbstractAssetVault {
    using TransientStateLibrary for IPoolManager;
    using StateLibrary for IPoolManager;
    using CurrencySettler for Currency;
    using SafeCast for *;
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @dev The pool key for the hook. Note that the hook supports only one pool key.
    PoolKey private _poolKey;

    /// @dev The total amount of accrued yields in the hook.
    uint256 private _accruedYieldsCurrency0;
    uint256 private _accruedYieldsCurrency1;

    /// @dev Error thrown when attempting to add or remove zero liquidity.
    error ZeroLiquidity();

    /// @dev Error thrown when trying to initialize a pool that has already been initialized.
    error AlreadyInitialized();

    /// @dev Error thrown when attempting to interact with a pool that has not been initialized.
    error NotInitialized();

    /// @dev Error thrown when the message value doesn't match the expected amount for native ETH deposits.
    error InvalidMsgValue();

    /// @dev Error thrown when an excess ETH refund fails.
    error RefundFailed();

    /// @dev Error thrown when the calculated amounts for liquidity modification operations are invalid.
    error InvalidAmounts();

    /**
     * @dev Emitted when a `sender` adds rehypothecated `liquidity` to the `poolKey` pool,
     *  transferring `amount0` of `currency0` and `amount1` of `currency1` to the hook.
     */
    event ReHypothecatedLiquidityAdded(
        address indexed sender, PoolKey indexed poolKey, uint128 liquidity, uint256 amount0, uint256 amount1
    );

    /**
     * @dev Emitted when a `sender` removes rehypothecated `liquidity` from the `poolKey` pool,
     *  receiving `amount0` of `currency0` and `amount1` of `currency1` from the hook.
     */
    event ReHypothecatedLiquidityRemoved(
        address indexed sender, PoolKey indexed poolKey, uint128 liquidity, uint256 amount0, uint256 amount1
    );

    /**
     * @dev Sets the `PoolManager` address.
     */
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    /**
     * @dev Returns the `poolKey` for the hook pool.
     */
    function getPoolKey() public view returns (PoolKey memory poolKey) {
        return _poolKey;
    }

    /**
     *  @inheritdoc AbstractAssetVault
     */
    function totalAssets() public view virtual override returns (uint256) {
        return _getMaximumLiquidityFromYieldSources();
    }

    /**
     * @dev Initialize the hook's `poolKey`. The stored key by the hook is unique and
     * should not be modified so that it can safely be used across the hook's lifecycle.
     */
    function _beforeInitialize(address, PoolKey calldata key, uint160) internal override returns (bytes4) {
        if (address(_poolKey.hooks) != address(0)) revert AlreadyInitialized();
        _poolKey = key;
        return this.beforeInitialize.selector;
    }

    /**
     * @dev Adds rehypothecated liquidity to the pool and mints shares to the caller.
     *
     * Converts the target `liquidity` into required token amounts, transfers assets from the user,
     * deposits them into yield sources for rehypothecation, and mints vault shares representing
     * the user's share of the hook position.
     *
     * The liquidity is not directly added to the Uniswap pool but held in yield sources, allowing
     * the hook to deploy it dynamically during swaps while generating yield when idle.
     *
     * returns a balance `delta` representing the assets deposited into the hook.
     *
     * Requirements:
     * - Pool must be initialized
     * - Sender must have sufficient token balances
     * - Sender must have approved the hook to spend the required tokens
     */
    function addReHypothecatedLiquidity(uint128 liquidity) public payable virtual returns (BalanceDelta delta) {
        if (address(_poolKey.hooks) == address(0)) revert NotInitialized();
        if (liquidity == 0) revert ZeroLiquidity();

        uint256 maxAssets = maxDeposit(msg.sender);
        if (liquidity > maxAssets) {
            revert AbstractAssetVaultExceededMaxDeposit(msg.sender, liquidity, maxAssets);
        }
        uint256 shares = previewDeposit(liquidity);

        // Calculate the amounts required to achieve the target liquidity based on the current pool price
        (uint256 amount0, uint256 amount1) = _getAmountsForLiquidity(liquidity);

        _transferFromSenderToHook(_poolKey.currency0, amount0, msg.sender);
        _transferFromSenderToHook(_poolKey.currency1, amount1, msg.sender);

        _depositToYieldSource(_poolKey.currency0, amount0);
        _depositToYieldSource(_poolKey.currency1, amount1);

        _mint(msg.sender, shares);

        emit ReHypothecatedLiquidityAdded(msg.sender, _poolKey, liquidity, amount0, amount1);

        return toBalanceDelta(-int256(amount0).toInt128(), -int256(amount1).toInt128());
    }

    /**
     * @dev Removes rehypothecated liquidity from yield sources and burns caller's shares.
     *
     * Converts the target `liquidity` into required token amounts, withdraws assets from
     * yield sources, burns vault shares from the caller, and transfers the underlying
     * tokens back to them.
     *
     * The liquidity is withdrawn from yield sources where it was generating yield,
     * allowing users to exit their rehypothecated position and reclaim their assets.
     *
     * @param liquidity The amount of liquidity units to remove
     * @return delta The balance changes representing assets withdrawn from the hook
     *
     * Requirements:
     * - Pool must be initialized
     * - Sender must have sufficient shares for the desired liquidity withdrawal
     */
    function removeReHypothecatedLiquidity(uint128 liquidity) public virtual returns (BalanceDelta delta) {
        if (address(_poolKey.hooks) == address(0)) revert NotInitialized();
        if (liquidity == 0) revert ZeroLiquidity();

        uint256 maxAssets = maxWithdraw(msg.sender);
        if (liquidity > maxAssets) {
            revert AbstractAssetVaultExceededMaxWithdraw(msg.sender, liquidity, maxAssets);
        }
        uint256 shares = previewWithdraw(liquidity);

        _burn(msg.sender, shares);

        // Calculate the amounts to be withdrawn that equals the target liquidity based on the current pool price
        (uint256 amount0, uint256 amount1) = _getAmountsForLiquidity(liquidity);

        _withdrawFromYieldSource(_poolKey.currency0, amount0);
        _withdrawFromYieldSource(_poolKey.currency1, amount1);

        _transferFromHookToSender(_poolKey.currency0, amount0, msg.sender);
        _transferFromHookToSender(_poolKey.currency1, amount1, msg.sender);

        emit ReHypothecatedLiquidityRemoved(msg.sender, _poolKey, liquidity, amount0, amount1);

        return toBalanceDelta(int256(amount0).toInt128(), int256(amount1).toInt128());
    }

    /* 
    * @dev Collects accrued yields from the yield sources.
    * Rebalances the amounts in yield sources to the pool price,
    * taking any excedent amounts as accrued yields.
    */
    function collectAccruedYields() public virtual {
        _collectAccruedYields();
    }

    /**
     * @dev Rebalances the hook-owned balances deposited in yield sources to maintain accurate share accounting.
     *
     * Calculates the maximum usable liquidity units from the hook-owned balances, constrained by the current
     * pool price and the hook's position range. Any excess tokens that cannot contribute to liquidity provision
     * are withdrawn as accrued yields to be claimed by liquidity providers.
     *
     * WARNING: This rebalancing is critical for accurate share accounting. Since `_getLiquidityFromYieldSources()`
     * liquidity units are used for computing shares, any unusable tokens must be withdrawn from yield sources
     * to prevent distorting the shares-to-liquidity ratio.
     */
    function _collectAccruedYields() internal virtual {
        uint256 totalAmount0 = _getAmountInYieldSource(_poolKey.currency0);
        uint256 totalAmount1 = _getAmountInYieldSource(_poolKey.currency1);
        uint128 usableLiquidity = _getLiquidityForAmounts(totalAmount0, totalAmount1);
        (uint256 usableAmount0, uint256 usableAmount1) = _getAmountsForLiquidity(usableLiquidity);

        uint256 excessAmount0 = totalAmount0 - usableAmount0;
        uint256 excessAmount1 = totalAmount1 - usableAmount1;

        if (excessAmount0 > 0) {
            console.log("withdrawing excess amount0", excessAmount0);
            _withdrawFromYieldSource(_poolKey.currency0, excessAmount0);
            _accruedYieldsCurrency0 += excessAmount0;
        }
        if (excessAmount1 > 0) {
            console.log("withdrawing excess amount1", excessAmount1);
            _withdrawFromYieldSource(_poolKey.currency1, excessAmount1);
            _accruedYieldsCurrency1 += excessAmount1;
        }
    }

    /**
     * @dev Returns the usable hook-owned liquidity from the amounts currently deposited in the yield sources.
     *
     * This function automatically rebalances yield sources to ensure accurate liquidity calculations, then
     * computes the maximum liquidity that can be provided using the current pool price and position range.
     * Any excess tokens that cannot contribute to liquidity provision are moved to accrued yields.
     *
     * NOTE: The returned liquidity represents only the usable portion after rebalancing. Excess tokens
     * continue earning yield as accrued yields but don't contribute to the liquidity calculation.
     */
    function _getMaximumLiquidityFromYieldSources() internal view virtual returns (uint256) {
        uint256 totalAmount0 = _getAmountInYieldSource(_poolKey.currency0);
        uint256 totalAmount1 = _getAmountInYieldSource(_poolKey.currency1);
        return _getLiquidityForAmounts(totalAmount0, totalAmount1);
    }

    /**
     * @dev Retrieves the current `liquidity` of the hook owned liquidity position in the `_poolKey` pool.
     *
     * WARNING: Given that we are doing just-in-time liquidity provisioning, the liquidity will only be inside the
     * hook's position between `beforeSwap` and `afterSwap`. It will be zero in any other point in the hook lifecycle.
     */
    function _getHookPositionLiquidity() internal view virtual returns (uint128 liquidity) {
        bytes32 positionKey = Position.calculatePositionKey(address(this), getTickLower(), getTickUpper(), bytes32(0));
        return poolManager.getPositionLiquidity(_poolKey.toId(), positionKey);
    }

    /**
     * @dev Hook executed before a swap operation to provide liquidity from rehypothecated assets.
     *
     * This function gets the amount of liquidity to be provided from yield sources and temporarily
     * adds it to the pool, in a Just-in-Time provision of liquidity.
     *
     * Note that at this point there are no actual transfers of tokens happening to the pool, instead,
     * thanks to the Flash Accounting model this addition creates a currencyDelta to the hook, which
     * must be settled during the `_afterSwap` function before locking the poolManager again.
     */
    function _beforeSwap(
        address, /* sender */
        PoolKey calldata, /* key */
        SwapParams calldata params, /* params */
        bytes calldata /* hookData */
    ) internal virtual override returns (bytes4, BeforeSwapDelta, uint24) {
        // Get the total hook-owned liquidity from the amounts currently deposited in the yield sources
        uint256 liquidity = _getMaximumLiquidityFromYieldSources();

        console.log("params.zeroForOne", params.zeroForOne);
        console.log("params.amountSpecified", params.amountSpecified);
        console.log("params.sqrtPriceLimitX96", params.sqrtPriceLimitX96);
        console.log("liquidity from yield sources", liquidity);

        // Add liquidity to the pool (in a Just-in-Time provision of liquidity)
        if (liquidity > 0) _modifyLiquidity(liquidity.toInt256());

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /**
     * @dev Hook executed after a swap operation to remove temporary liquidity and rebalance assets.
     *
     * This function removes the liquidity that was temporarily added in `_beforeSwap`, and resolves
     * the hook's deltas in each currency in order to zero them.
     */
    function _afterSwap(
        address, /* sender */
        PoolKey calldata key,
        SwapParams calldata, /* params */
        BalanceDelta, /* delta */
        bytes calldata /* hookData */
    ) internal virtual override returns (bytes4, int128) {
        // Remove all of the hook owned liquidity from the pool
        uint128 liquidity = _getHookPositionLiquidity();
        if (liquidity > 0) {
            _modifyLiquidity(-liquidity.toInt256());

            // Take or settle any pending deltas with the PoolManager
            console.log("resolving hook delta for currency0");
            _resolveHookDelta(key.currency0);
            console.log("resolving hook delta for currency1");
            _resolveHookDelta(key.currency1);
            console.log("after swap completed");
        }

        return (this.afterSwap.selector, 0);
    }

    /**
     * @dev Returns the lower tick boundary for the hook's liquidity position.
     */
    function getTickLower() public view virtual returns (int24) {
        return TickMath.minUsableTick(_poolKey.tickSpacing);
    }

    /**
     * @dev Returns the upper tick boundary for the hook's liquidity position.
     */
    function getTickUpper() public view virtual returns (int24) {
        return TickMath.maxUsableTick(_poolKey.tickSpacing);
    }

    /**
     * @dev Calculates the amounts required for adding a specific amount of liquidity.
     *
     * This function uses the current price and tick boundaries to determine the exact amounts
     * of both currencies needed to achieve the target liquidity.
     */
    function _getAmountsForLiquidity(uint128 liquidity)
        internal
        view
        virtual
        returns (uint256 amount0, uint256 amount1)
    {
        (uint160 currentSqrtPriceX96,,,) = poolManager.getSlot0(_poolKey.toId());
        return LiquidityAmounts.getAmountsForLiquidity(
            currentSqrtPriceX96,
            TickMath.getSqrtPriceAtTick(getTickLower()),
            TickMath.getSqrtPriceAtTick(getTickUpper()),
            liquidity
        );
    }

    /**
     * @dev Calculates the amount of liquidity required for a given amount of tokens.
     *
     * This function uses the current price and tick boundaries to determine the exact amount of liquidity
     * required to achieve the target amounts of both currencies.
     */
    function _getLiquidityForAmounts(uint256 amount0, uint256 amount1)
        internal
        view
        virtual
        returns (uint128 liquidity)
    {
        (uint160 currentSqrtPriceX96,,,) = poolManager.getSlot0(_poolKey.toId());
        return LiquidityAmounts.getLiquidityForAmounts(
            currentSqrtPriceX96,
            TickMath.getSqrtPriceAtTick(getTickLower()),
            TickMath.getSqrtPriceAtTick(getTickUpper()),
            amount0,
            amount1
        );
    }

    /**
     * @dev Modifies the hook's liquidity position in the pool.
     *
     * This function adds or removes liquidity from the hook's position using the pool manager.
     *
     * Positive liquidityDelta adds liquidity, while negative removes it.
     */
    function _modifyLiquidity(int256 liquidityDelta) internal virtual returns (BalanceDelta delta) {
        (delta,) = poolManager.modifyLiquidity(
            _poolKey,
            ModifyLiquidityParams({
                tickLower: getTickLower(),
                tickUpper: getTickUpper(),
                liquidityDelta: liquidityDelta,
                salt: bytes32(0)
            }),
            ""
        );
    }

    /**
     * @dev Takes or settles any pending `currencyDelta` amount with the poolManager, effectively
     * resolving the Flash Accounting requirements before locking the poolManager again.
     */
    function _resolveHookDelta(Currency currency) internal virtual {
        console.log("resolving hook delta for", Currency.unwrap(currency));
        int256 currencyDelta = poolManager.currencyDelta(address(this), currency);
        if (currencyDelta > 0) {
            currency.take(poolManager, address(this), currencyDelta.toUint256(), false);
            _depositToYieldSource(currency, currencyDelta.toUint256());
            console.log("deposited currencyDelta to yield source", currencyDelta.toUint256());
        }
        if (currencyDelta < 0) {
            _withdrawFromYieldSource(currency, (-currencyDelta).toUint256());
            currency.settle(poolManager, address(this), (-currencyDelta).toUint256(), false);
            console.log("withdrawn currencyDelta from yield source", (-currencyDelta).toUint256());
        }
    }

    /// @dev Transfers the `amount` of `currency` from the `sender` to the hook.
    function _transferFromSenderToHook(Currency currency, uint256 amount, address sender) internal virtual {
        if (currency.isAddressZero()) {
            if (msg.value < amount) revert InvalidMsgValue();
            uint256 refund = msg.value - amount;
            if (refund > 0) {
                (bool success,) = msg.sender.call{value: refund}("");
                if (!success) revert RefundFailed();
            }
        } else {
            IERC20(Currency.unwrap(currency)).safeTransferFrom(sender, address(this), amount);
        }
    }

    function _transferFromHookToSender(Currency currency, uint256 amount, address sender) internal virtual {
        currency.transfer(sender, amount);
    }

    /**
     * @dev Returns the `yieldSource` address for a given `currency`.
     *
     * Note: Must be implemented and adapted for the desired type of yield sources, such as
     *  ERC-4626 Vaults, or any custom DeFi protocol interface, optionally handling native currency.
     */
    function getCurrencyYieldSource(Currency currency) public view virtual returns (address yieldSource);

    /**
     * @dev Deposits a specified `amount` of `currency` into its corresponding yield source.
     *
     * This function must take the `amount` of `currency` from the sender and deposit it into the yield source.
     *
     * Note: Must be implemented and adapted for the desired type of yield sources, such as
     *  ERC-4626 Vaults, or any custom DeFi protocol interface, optionally handling native currency.
     */
    function _depositToYieldSource(Currency currency, uint256 amount) internal virtual;

    /**
     * @dev Withdraws a specified `amount` of `currency` from its corresponding yield source.
     *
     * This function must withdraw the `amount` of `currency` from the yield source and return them
     * to the hook for further processing (e.g., transferring to users or adding to pool liquidity).
     *
     * Note: Must be implemented and adapted for the desired type of yield sources, such as
     *  ERC-4626 Vaults, or any custom DeFi protocol interface, optionally handling native currency.
     */
    function _withdrawFromYieldSource(Currency currency, uint256 amount) internal virtual;

    /**
     * @dev Gets the `amount` of `currency` deposited in its corresponding yield source.
     *
     * This function must return the `amount` of `currency` deposited in its corresponding yield source.
     *
     * Note: Must be implemented and adapted for the desired type of yield sources, such as
     *  ERC-4626 Vaults, or any custom DeFi protocol interface, optionally handling native currency.
     */
    function _getAmountInYieldSource(Currency currency) internal view virtual returns (uint256 amount);

    /**
     * Set the hooks permissions, specifically `beforeInitialize`, `beforeSwap`, `afterSwap`.
     * @return permissions The permissions for the hook.
     */
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory permissions) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}

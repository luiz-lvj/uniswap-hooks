// SPDX-License-Identifier: MIT
// OpenZeppelin Uniswap Hooks (last updated v1.2.0) (src/general/ReHypothecationHook.sol)

pragma solidity ^0.8.24;

// External imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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

/**
 * @dev A Uniswap V4 hook that enables rehypothecation of liquidity positions.
 *
 * This hook allows users to deposit assets into yield-generating sources (e.g., ERC-4626 vaults)
 * while still making the same capital available as swapping liquidity in Uniswap pools.
 * Assets earn yield in yield sources most of the time, but are temporarily surfaced as pool
 * liquidity through Just-in-Time (JIT) provisioning during swaps.
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
 * - After swaps, assets are rebalanced back into yield sources to continue earning yield.
 * - Supports both ERC20 tokens and native ETH (with proper integration).
 *
 * NOTE: By default, the hook liquidity position is placed in the entire curve range. Override
 * the `getHookPositionTickLower` and `getHookPositionTickUpper` functions to customize the position.
 *
 * NOTE: By default, both rehypothecated and cannonical liquidity modifications are allowed. In order to
 * enforce rehypothecated liquidity modifications only, override `beforeAddLiquidity` and `beforeRemoveLiquidity`
 * to revert.
 *
 * WARNING: This is experimental software and is provided on an "as is" and "as available" basis.
 * We do not give any warranties and will not be liable for any losses incurred through any use of
 * this code base.
 * _Available since v1.1.0_
 */
abstract contract ReHypothecationHook is BaseHook, ERC20 {
    using TransientStateLibrary for IPoolManager;
    using StateLibrary for IPoolManager;
    using CurrencySettler for Currency;
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// @dev The pool key for the hook. Note that the hook supports only one pool key.
    PoolKey private _poolKey;

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

    /// @dev Error thrown when attempting to use an unsupported currency.
    error UnsupportedCurrency();

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
     * @dev Initialize the hook's `poolKey`. The stored key by the hook is unique and
     * should not be modified so that it can safely be used across the hook's lifecycle.
     */
    function _beforeInitialize(address, PoolKey calldata key, uint160) internal override returns (bytes4) {
        if (address(_poolKey.hooks) != address(0)) revert AlreadyInitialized();
        _poolKey = key;
        return this.beforeInitialize.selector;
    }

    /**
     * @dev Adds rehypothecated `liquidity` to the pool, returns the caller's `delta`, and mints ERC20 shares to them.
     *
     * This function calculates the required amounts of both currencies based on the desired liquidity, transfers the assets
     * from the user, deposits them into yield sources, and mints shares to the user representing the user's position.
     *
     * Returns a balance `delta` representing the assets deposited into the hook.
     *
     * Requirements:
     * - Pool must be initialized
     *
     * Note: The hook might accept native currency, in which case the function `_depositToYieldSource` must be
     * overridden to handle it.
     */
    function addReHypothecatedLiquidity(uint128 liquidity) public payable virtual returns (BalanceDelta delta) {
        if (address(_poolKey.hooks) == address(0)) revert NotInitialized();
        if (liquidity == 0) revert ZeroLiquidity();

        (uint256 amount0, uint256 amount1) = _getAmountsForLiquidity(liquidity);

        _depositToYieldSource(_poolKey.currency0, amount0);
        _depositToYieldSource(_poolKey.currency1, amount1);

        _mint(msg.sender, _liquidityToShares(liquidity));

        emit ReHypothecatedLiquidityAdded(msg.sender, _poolKey, liquidity, amount0, amount1);

        return toBalanceDelta(int256(amount0).toInt128(), int256(amount1).toInt128());
    }

    /**
     * @dev Removes rehypothecated `liquidity` for a given sender and burns their shares.
     *
     * This function calculates the required amounts of both currencies based on the desired liquidity
     * to be removed, withdraws the assets from the yield sources, and burns the shares from the user.
     *
     * Returns a balance `delta` representing the assets withdrawn from the hook.
     *
     * Requirements:
     * - Pool must be initialized
     * - Sender must have enough shares to remove the desired liquidity
     *
     */
    function removeReHypothecatedLiquidity(uint128 liquidity) public virtual returns (BalanceDelta delta) {
        if (address(_poolKey.hooks) == address(0)) revert NotInitialized();
        if (liquidity == 0) revert ZeroLiquidity();

        (uint256 amount0, uint256 amount1) = _getAmountsForLiquidity(liquidity);

        _burn(msg.sender, _liquidityToShares(liquidity));

        _withdrawFromYieldSource(_poolKey.currency0, amount0);
        _withdrawFromYieldSource(_poolKey.currency1, amount1);

        emit ReHypothecatedLiquidityRemoved(msg.sender, _poolKey, liquidity, amount0, amount1);

        return toBalanceDelta(int256(amount0).toInt128(), int256(amount1).toInt128());
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
        PoolKey calldata key,
        SwapParams calldata, /* params */
        bytes calldata /* hookData */
    ) internal virtual override returns (bytes4, BeforeSwapDelta, uint24) {
        uint256 amount0 = _getAmountInYieldSource(key.currency0);
        uint256 amount1 = _getAmountInYieldSource(key.currency1);
        uint128 liquidity = _getLiquidityForAmounts(amount0, amount1);

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
        uint128 liquidity = _getHookPositionLiquidity(key);
        if (liquidity > 0) {
            _modifyLiquidity(-liquidity.toInt256());

            // Take or settle any pending deltas with the PoolManager
            _resolveHookDelta(key.currency0);
            _resolveHookDelta(key.currency1);
        }

        return (this.afterSwap.selector, 0);
    }

    /**
     * @dev Converts liquidity to shares.
     *
     * Utilizes a default ratio of 1:1 between liquidity and shares, can be overridden
     * in order to implement a different calculation.
     */
    function _liquidityToShares(uint128 liquidity) internal view virtual returns (uint256) {
        return liquidity;
    }

    /**
     * @dev Returns the lower tick boundary for the hook's liquidity position.
     */
    function getHookPositionTickLower() public view virtual returns (int24) {
        return TickMath.minUsableTick(_poolKey.tickSpacing);
    }

    /**
     * @dev Returns the upper tick boundary for the hook's liquidity position.
     */
    function getHookPositionTickUpper() public view virtual returns (int24) {
        return TickMath.maxUsableTick(_poolKey.tickSpacing);
    }

    /**
     * @dev Calculates the amounts required for adding a specific amount of liquidity.
     *
     * This function uses the current pool state and desired liquidity to determine
     * the exact amounts of both currencies needed to achieve the target liquidity.
     *
     */
    function _getAmountsForLiquidity(uint128 liquidity) internal virtual returns (uint256 amount0, uint256 amount1) {
        (uint160 currentSqrtPriceX96,,,) = poolManager.getSlot0(_poolKey.toId());
        return LiquidityAmounts.getAmountsForLiquidity(
            currentSqrtPriceX96,
            TickMath.getSqrtPriceAtTick(getHookPositionTickLower()),
            TickMath.getSqrtPriceAtTick(getHookPositionTickUpper()),
            liquidity
        );
    }

    /**
     * @dev Calculates the amount of liquidity required for a given amount of tokens.
     */
    function _getLiquidityForAmounts(uint256 amount0, uint256 amount1) internal virtual returns (uint128 liquidity) {
        (uint160 currentSqrtPriceX96,,,) = poolManager.getSlot0(_poolKey.toId());
        return LiquidityAmounts.getLiquidityForAmounts(
            currentSqrtPriceX96,
            TickMath.getSqrtPriceAtTick(getHookPositionTickLower()),
            TickMath.getSqrtPriceAtTick(getHookPositionTickUpper()),
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
                tickLower: getHookPositionTickLower(),
                tickUpper: getHookPositionTickUpper(),
                liquidityDelta: liquidityDelta,
                salt: bytes32(0)
            }),
            ""
        );
    }

    /**
     * @dev Retrieves the current `liquidity` of the hook owned liquidity position in the `key` pool.
     */
    function _getHookPositionLiquidity(PoolKey calldata key) internal virtual returns (uint128 liquidity) {
        bytes32 positionKey = Position.calculatePositionKey(
            address(this), getHookPositionTickLower(), getHookPositionTickUpper(), bytes32(0)
        );
        return poolManager.getPositionLiquidity(key.toId(), positionKey);
    }

    /**
     * @dev Takes or settles any pending `currencyDelta` amount with the poolManager, effectively
     * resolving the Flash Accounting requirements before locking the poolManager again.
     */
    function _resolveHookDelta(Currency currency) internal virtual {
        int256 currencyDelta = poolManager.currencyDelta(address(this), currency);
        if (currencyDelta > 0) {
            currency.take(poolManager, address(this), currencyDelta.toUint256(), false);
            _depositToYieldSource(currency, currencyDelta.toUint256());
        }
        if (currencyDelta < 0) {
            _withdrawFromYieldSource(currency, (-currencyDelta).toUint256());
            currency.settle(poolManager, address(this), (-currencyDelta).toUint256(), false);
        }
    }

    /**
     * @dev Returns the yield source address for a given currency.
     *
     * Note: Should be overridden and adapted for other types of yield sources apart from ERC-4626,
     *  such as custom DeFi protocol interfaces, or handling native currency.
     */
    function getYieldSourceForCurrency(Currency currency) public view virtual returns (address);

    /**
     * @dev Deposits a specified `amount` of `currency` into its corresponding yield source.
     *
     * Note: Should be overridden and adapted for other types of yield sources apart from ERC-4626,
     *  such as custom DeFi protocol interfaces, or handling native currency.
     */
    function _depositToYieldSource(Currency currency, uint256 amount) internal virtual {
        // In this ERC4626 implementation, native currency is not supported.
        if (currency.isAddressZero()) revert UnsupportedCurrency();
        IERC20 token = IERC20(Currency.unwrap(currency));

        IERC4626 yieldSource = IERC4626(getYieldSourceForCurrency(currency));
        if (address(yieldSource) == address(0)) revert UnsupportedCurrency();

        token.safeTransferFrom(msg.sender, address(this), amount);
        token.approve(address(yieldSource), amount);
        yieldSource.deposit(amount, address(this));
    }

    /**
     * @dev Withdraws a specified `amount` of `currency` from its corresponding yield source.
     *
     * This function withdraws assets from the yield source and returns them to the hook
     * for further processing (e.g., transferring to users or adding to pool liquidity).
     *
     * Note: Should be overridden and adapted for other types of yield sources apart from ERC-4626,
     *  such as custom DeFi protocol interfaces, or handling native currency.
     */
    function _withdrawFromYieldSource(Currency currency, uint256 amount) internal virtual {
        IERC4626 yieldSource = IERC4626(getYieldSourceForCurrency(currency));
        if (address(yieldSource) == address(0)) revert UnsupportedCurrency();

        yieldSource.withdraw(amount, address(this), address(this));
        currency.transfer(msg.sender, amount);
    }

    /**
     * @dev Gets the `amount` of `currency` deposited in its corresponding yield source.
     *
     * Note: Should be overridden and adapted for other types of yield sources apart from ERC-4626,
     *  such as custom DeFi protocol interfaces, or handling native currency.
     */
    function _getAmountInYieldSource(Currency currency) internal virtual returns (uint256 amount) {
        IERC4626 yieldSource = IERC4626(getYieldSourceForCurrency(currency));
        uint256 yieldSourceShares = yieldSource.balanceOf(address(this));
        return yieldSource.convertToAssets(yieldSourceShares);
    }

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

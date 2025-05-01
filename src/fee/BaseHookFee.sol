// SPDX-License-Identifier: MIT
// OpenZeppelin Uniswap Hooks (last updated v0.1.0) (src/fee/BaseHookFee.sol)

pragma solidity ^0.8.24;

// internal imports
import {IHookEvents} from "../interfaces/IHookEvents.sol";
import {BaseHook} from "../base/BaseHook.sol";
import {CurrencySettler} from "../utils/CurrencySettler.sol";

// external imports
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

abstract contract BaseHookFee is BaseHook, IHookEvents {
    using SafeCast for uint256;
    using CurrencySettler for Currency;

    uint256 internal constant MAX_FEE = 1e6;

    error FeeTooHigh();

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function _getHookFee(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal view virtual returns (uint256);

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal virtual override returns (bytes4, int128) {
        (Currency unspecified, int128 unspecifiedAmount) = (params.amountSpecified < 0 == params.zeroForOne)
            ? (key.currency1, delta.amount1())
            : (key.currency0, delta.amount0());

        if (unspecifiedAmount == 0) {
            return (this.afterSwap.selector, 0);
        }

        if (unspecifiedAmount < 0) {
            unspecifiedAmount = -unspecifiedAmount;
        }

        uint256 fee = _getHookFee(sender, key, params, hookData);

        if (fee == 0) return (this.afterSwap.selector, 0);

        if (fee > MAX_FEE) revert FeeTooHigh();

        uint256 feeAmount = FullMath.mulDiv(uint256(uint128(unspecifiedAmount)), fee, MAX_FEE);

        if (feeAmount > 0) {
            unspecified.take(poolManager, address(this), feeAmount, false);
        }

        // Emit the swap event with the amounts ordered correctly
        if (unspecified == key.currency0) {
            emit HookFee(PoolId.unwrap(key.toId()), sender, feeAmount.toUint128(), 0);
        } else {
            emit HookFee(PoolId.unwrap(key.toId()), sender, 0, feeAmount.toUint128());
        }

        return (this.afterSwap.selector, feeAmount.toInt128());
    }

    /**
     * @dev Set the hook permissions, specifically {afterSwap} and {afterSwapReturnDelta}.
     *
     * @return permissions The hook permissions.
     */
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory permissions) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}

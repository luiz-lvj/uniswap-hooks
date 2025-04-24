// SPDX-License-Identifier: MIT
// OpenZeppelin Uniswap Hooks (last updated v0.1.1) (src/general/LiquidityPenaltyHook.sol)

pragma solidity ^0.8.24;

import {BaseHook} from "../base/BaseHook.sol";
import {Pool} from "v4-core/src/libraries/Pool.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Position} from "v4-core/src/libraries/Position.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {CurrencySettler} from "src/utils/CurrencySettler.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

abstract contract ReHypothecationHook is BaseHook {
    using StateLibrary for IPoolManager;
    using CurrencySettler for Currency;
    using SafeCast for uint256;

    struct ReHypothecatedPosition {
        uint256 liquidityTotal;
        mapping(address => uint256) liquidity;
    }

    mapping(PoolId => ReHypothecatedPosition) public reHypothecatedPositions;


    error ZeroLiquidity();

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function addReHypothecatedLiquidity(PoolKey calldata key, int256 amount0, int256 amount1)
        external
    {
        uint256 liquidity = _rehypothecateLiquidity(key, amount0, amount1);
        if (liquidity == 0) revert ZeroLiquidity();

        reHypothecatedPositions[key.toId()].liquidityTotal += liquidity;
        reHypothecatedPositions[key.toId()].liquidity[msg.sender] += liquidity;


    }

    function removeReHypothecatedLiquidity(PoolKey calldata key, address owner) external {
        uint256 liquidity = reHypothecatedPositions[key.toId()].liquidity[owner];
        if (liquidity == 0) revert ZeroLiquidity();


        (uint256 amount0, uint256 amount1) = _retrieveReHypothecatedLiquidity(key, owner, liquidity);

        reHypothecatedPositions[key.toId()].liquidityTotal -= liquidity;
        reHypothecatedPositions[key.toId()].liquidity[owner] = 0;

        key.currency0.transfer(owner, amount0);
        key.currency1.transfer(owner, amount1);
    }

    function _rehypothecateLiquidity(PoolKey calldata key, int256 amount0, int256 amount1) internal virtual returns (uint256 liquidity);

    function _retrieveReHypothecatedLiquidity(PoolKey calldata key, address owner, uint256 liquidity) internal virtual returns (uint256 amount0, uint256 amount1);

    function _beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) internal virtual override returns (bytes4, BeforeSwapDelta, uint24){
        if (reHypothecatedPositions[key.toId()].liquidityTotal > 0) {
            (uint256 liquidityToUse, int24 tickLower, int24 tickUpper) = _getLiquidityToUse(key, params);

            if(liquidityToUse > 0) {
                poolManager.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams({
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: liquidityToUse.toInt256(),
                    salt: bytes32(0)
                }), "");
            }
        }

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }


    function _getLiquidityToUse(PoolKey calldata key, IPoolManager.SwapParams calldata params) internal virtual returns (uint256 liquidity, int24 tickLower, int24 tickUpper);
    
    /**
     * Set the hooks permissions, specifically `afterAddLiquidity`, `afterRemoveLiquidity` and `afterRemoveLiquidityReturnDelta`.
     *
     * @return permissions The permissions for the hook.
     */
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory permissions) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: true
        });
    }
}

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



    uint256 public totalShares;
    mapping(address => uint256) public shares;

    uint128 private JITLiquidity;

    int24 private JITTickLower;
    int24 private JITTickUpper;


    error ZeroLiquidity();

    error AlreadyInitialized();


    PoolKey public poolKey;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function addReHypothecatedLiquidity(PoolKey calldata key, int256 amount0, int256 amount1)
        external
    {
        uint256 sharesAmount = _rehypothecateLiquidity(key, amount0, amount1);
        if (sharesAmount == 0) revert ZeroLiquidity();

        _increaseShares(msg.sender, sharesAmount);

    }

    function removeReHypothecatedLiquidity(PoolKey calldata key, address owner) external {
        uint256 sharesAmount = shares[owner];
        if (sharesAmount == 0) revert ZeroLiquidity();


        (uint256 amount0, uint256 amount1) = _retrieveReHypothecatedLiquidity(key, owner);

        _decreaseShares(owner, sharesAmount);

        key.currency0.transfer(owner, amount0);
        key.currency1.transfer(owner, amount1);
    }

    function _rehypothecateLiquidity(PoolKey calldata key, int256 amount0, int256 amount1) internal virtual returns (uint256 sharesAmount);

    function _retrieveReHypothecatedLiquidity(PoolKey calldata key, address owner) internal virtual returns (uint256 amount0, uint256 amount1);

    function _beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) internal virtual override returns (bytes4, BeforeSwapDelta, uint24){
        if (totalShares > 0) {
            (uint256 liquidityToUse, int24 tickLower, int24 tickUpper) = _getLiquidityToUse(params);

            JITLiquidity = liquidityToUse;
            JITTickLower = tickLower;
            JITTickUpper = tickUpper;

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


    function _increaseShares(address owner, uint256 amountShares) private {
        totalShares += amountShares;
        shares[owner] += amountShares;
    }

    function _decreaseShares(address owner, uint256 amountShares) private {

        totalShares -= amountShares;
        shares[owner] -= amountShares;
    }

    /**
     * @dev Initialize the hook's pool key. The stored key should act immutably so that
     * it can safely be used across the hook's functions.
     */
    function _beforeInitialize(address, PoolKey calldata key, uint160) internal override returns (bytes4) {
        // Check if the pool key is already initialized
        if (address(poolKey.hooks) != address(0)) revert AlreadyInitialized();

        // Store the pool key to be used in other functions
        poolKey = key;
        return this.beforeInitialize.selector;
    }


    function _afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal virtual override returns (bytes4, int128) {
        if(JITLiquidity > 0) {
            poolManager.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams({
                tickLower: JITTickLower,
                tickUpper: JITTickUpper,
                liquidityDelta: -int256(uint256(JITLiquidity)),
                salt: bytes32(0)
            }), "");
        }

        JITLiquidity = 0;
        JITTickLower = 0;
        JITTickUpper = 0;

        int256 currencyDelta0 = poolManager.currencyDelta(address(this), key.currency0);
        int256 currencyDelta1 = poolManager.currencyDelta(address(this), key.currency1);

        if(currencyDelta0 > 0){
            key.currency0.take();
        }
        
        


        return (this.afterSwap.selector, 0);

    }





    function _getLiquidityToUse(IPoolManager.SwapParams calldata params) internal virtual returns (uint256 liquidity, int24 tickLower, int24 tickUpper);
    
    /**
     * Set the hooks permissions, specifically `afterAddLiquidity`, `afterRemoveLiquidity` and `afterRemoveLiquidityReturnDelta`.
     *
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

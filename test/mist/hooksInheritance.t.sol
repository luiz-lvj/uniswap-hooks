// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// // External
// import {BaseHook} from "src/base/BaseHook.sol";
// import {LimitOrderHook} from "src/general/LimitOrderHook.sol";
// import {BaseHookFee} from "src/fee/BaseHookFee.sol";
// import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
// import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
// import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
// import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
// import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
// import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

// contract HookDoubleChildren is LimitOrderHook, BaseHookFee {
//     constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

//     function _afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick)
//         internal
//         override(LimitOrderHook, BaseHook)
//         returns (bytes4)
//     {
//         return super._afterInitialize(sender, key, sqrtPriceX96, tick);
//     }

//     function _afterSwap(
//         address sender,
//         PoolKey calldata key,
//         SwapParams calldata params,
//         BalanceDelta delta,
//         bytes calldata hookData
//     ) internal override(LimitOrderHook, BaseHookFee) returns (bytes4, int128) {
//         return super._afterSwap(sender, key, params, delta, hookData);
//     }

//     function _getHookFee(
//         address sender,
//         PoolKey calldata key,
//         SwapParams calldata params,
//         BalanceDelta delta,
//         bytes calldata hookData
//     ) internal view override(BaseHookFee) returns (uint24 fee) {
//         return 10;
//     }

//     function handleHookFees(Currency[] memory currencies) public override(BaseHookFee) {
//         return;
//     }

//     function getHookPermissions()
//         public
//         pure
//         override(LimitOrderHook, BaseHookFee)
//         returns (Hooks.Permissions memory permissions)
//     {
//         return Hooks.Permissions({
//             beforeInitialize: false,
//             afterInitialize: false,
//             beforeAddLiquidity: false,
//             afterAddLiquidity: false,
//             beforeRemoveLiquidity: false,
//             afterRemoveLiquidity: false,
//             beforeSwap: false,
//             afterSwap: true,
//             beforeDonate: false,
//             afterDonate: false,
//             beforeSwapReturnDelta: false,
//             afterSwapReturnDelta: true,
//             afterAddLiquidityReturnDelta: false,
//             afterRemoveLiquidityReturnDelta: false
//         });
//     }
// }

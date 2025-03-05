// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {AntiJITHook} from "src/general/AntiJITHook.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import { FullMath } from "v4-core/src/libraries/FullMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import { Position } from "v4-core/src/libraries/Position.sol";
import { FixedPoint128 } from "v4-core/src/libraries/FixedPoint128.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {console} from "forge-std/console.sol";

contract AntiJITHookTest is Test, Deployers {
    AntiJITHook hook;
    PoolKey noHookKey;
    uint24 fee = 1000; // 0.1%

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        hook = AntiJITHook(
            address(uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG))
        );
        deployCodeTo("src/general/AntiJITHook.sol:AntiJITHook", abi.encode(manager, 1), address(hook));

        (key,) = initPool(
            currency0, currency1, IHooks(address(hook)), fee, SQRT_PRICE_1_1
        );
        (noHookKey,) = initPool(currency0, currency1, IHooks(address(0)), fee, SQRT_PRICE_1_1);

        vm.label(Currency.unwrap(currency0), "currency0");
        vm.label(Currency.unwrap(currency1), "currency1");
    }

    function calculateExpectedFees(
        IPoolManager manager,
        PoolId poolId,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) public view returns (int128, int128) {
        
        bytes32 positionKey = Position.calculatePositionKey(owner, tickLower, tickUpper, salt);
        (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) = StateLibrary.getPositionInfo(manager, poolId, positionKey);

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = StateLibrary.getFeeGrowthInside(manager, poolId, tickLower, tickUpper);

        uint256 feesExpected0 = FullMath.mulDiv(feeGrowthInside0X128 - feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128);
        uint256 feesExpected1 = FullMath.mulDiv(feeGrowthInside1X128 - feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128);

        return (int128(int256(feesExpected0)), int128(int256(feesExpected1)));
    }


    function test_addLiquidity_noSwap() public {

        IPoolManager.ModifyLiquidityParams memory addLiquidityParams  = IPoolManager.ModifyLiquidityParams({
            tickLower: -600, 
            tickUpper: 600, 
            liquidityDelta: 1e18, 
            salt: 0
        });
        modifyLiquidityRouter.modifyLiquidity(key, addLiquidityParams, "");
        modifyLiquidityRouter.modifyLiquidity(noHookKey, addLiquidityParams, "");

        IPoolManager.ModifyLiquidityParams memory removeLiquidityParams = IPoolManager.ModifyLiquidityParams({
            tickLower: -600, 
            tickUpper: 600, 
            liquidityDelta: -1e17, 
            salt: 0
        });

        BalanceDelta deltaHook = modifyLiquidityRouter.modifyLiquidity(key, removeLiquidityParams, "");
        BalanceDelta deltaNoHook = modifyLiquidityRouter.modifyLiquidity(noHookKey, removeLiquidityParams, "");

        assertEq(BalanceDeltaLibrary.amount0(deltaHook), BalanceDeltaLibrary.amount0(deltaNoHook));
        assertEq(BalanceDeltaLibrary.amount1(deltaHook), BalanceDeltaLibrary.amount1(deltaNoHook));

    }
    

    function test_addLiquidity_SwapZeroForOne() public {

        IPoolManager.ModifyLiquidityParams memory addLiquidityParams  = IPoolManager.ModifyLiquidityParams({
            tickLower: -600, 
            tickUpper: 600, 
            liquidityDelta: 1e18, 
            salt: 0
        });


        modifyLiquidityRouter.modifyLiquidity(key, addLiquidityParams, "");
        modifyLiquidityRouter.modifyLiquidity(noHookKey, addLiquidityParams, "");

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -1e15, //exact input
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });
        swapRouter.swap(key, swapParams, testSettings, "");
        swapRouter.swap(noHookKey, swapParams, testSettings, "");

        (int128 feesExpected0, int128 feesExpected1) = calculateExpectedFees(manager, key.toId(), address(modifyLiquidityRouter), -600, 600, bytes32(0));



        IPoolManager.ModifyLiquidityParams memory removeLiquidityParams = IPoolManager.ModifyLiquidityParams({
            tickLower: -600, 
            tickUpper: 600, 
            liquidityDelta: -1e17, 
            salt: 0
        });

        BalanceDelta deltaHook = modifyLiquidityRouter.modifyLiquidity(key, removeLiquidityParams, "");
        BalanceDelta deltaNoHook = modifyLiquidityRouter.modifyLiquidity(noHookKey, removeLiquidityParams, "");


        assertEq(BalanceDeltaLibrary.amount0(deltaHook), BalanceDeltaLibrary.amount0(deltaNoHook) - feesExpected0);
        assertEq(BalanceDeltaLibrary.amount1(deltaHook), BalanceDeltaLibrary.amount1(deltaNoHook) - feesExpected1);
    }

    function test_addLiquidity_NoSwapZeroForOne() public {

        IPoolManager.ModifyLiquidityParams memory addLiquidityParams  = IPoolManager.ModifyLiquidityParams({
            tickLower: -600, 
            tickUpper: 600, 
            liquidityDelta: 1e18, 
            salt: 0
        });


        modifyLiquidityRouter.modifyLiquidity(key, addLiquidityParams, "");
        modifyLiquidityRouter.modifyLiquidity(noHookKey, addLiquidityParams, "");

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: -1e15, //exact input
            sqrtPriceLimitX96: MAX_PRICE_LIMIT
        });

        swapRouter.swap(key, swapParams, testSettings, "");
        swapRouter.swap(noHookKey, swapParams, testSettings, "");

        (int128 feesExpected0, int128 feesExpected1) = calculateExpectedFees(manager, key.toId(), address(modifyLiquidityRouter), -600, 600, bytes32(0));



        IPoolManager.ModifyLiquidityParams memory removeLiquidityParams = IPoolManager.ModifyLiquidityParams({
            tickLower: -600, 
            tickUpper: 600, 
            liquidityDelta: -1e17, 
            salt: 0
        });


        BalanceDelta deltaHook = modifyLiquidityRouter.modifyLiquidity(key, removeLiquidityParams, "");
        BalanceDelta deltaNoHook = modifyLiquidityRouter.modifyLiquidity(noHookKey, removeLiquidityParams, "");


        assertEq(BalanceDeltaLibrary.amount0(deltaHook), BalanceDeltaLibrary.amount0(deltaNoHook) - feesExpected0);
        assertEq(BalanceDeltaLibrary.amount1(deltaHook), BalanceDeltaLibrary.amount1(deltaNoHook) - feesExpected1);
    }
}
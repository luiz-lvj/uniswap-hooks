// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// External imports
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
// Internal imports
import {ReHypothecationHook} from "../../src/general/ReHypothecationHook.sol";
import {ReHypothecationERC4626Mock, ERC4626YieldSourceMock} from "../../src/mocks/ReHypothecationERC4626Mock.sol";
import {HookTest} from "../../test/utils/HookTest.sol";
import {BalanceDeltaAssertions} from "../../test/utils/BalanceDeltaAssertions.sol";
import {console} from "forge-std/console.sol";

contract ReHypothecationHookERC4626Test is HookTest, BalanceDeltaAssertions {
    using StateLibrary for IPoolManager;
    using SafeCast for *;
    using Math for *;

    ReHypothecationERC4626Mock hook;

    IERC4626 yieldSource0;
    IERC4626 yieldSource1;

    PoolKey noHookKey;

    address lp1 = makeAddr("lp1");
    address lp2 = makeAddr("lp2");

    uint24 fee = 1000; // 0.1%

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        yieldSource0 = IERC4626(new ERC4626YieldSourceMock(IERC20(Currency.unwrap(currency0)), "Yield Source 0", "Y0"));
        yieldSource1 = IERC4626(new ERC4626YieldSourceMock(IERC20(Currency.unwrap(currency1)), "Yield Source 1", "Y1"));

        hook = ReHypothecationERC4626Mock(
            address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG))
        );
        deployCodeTo(
            "src/mocks/ReHypothecationERC4626Mock.sol:ReHypothecationERC4626Mock",
            abi.encode(manager, address(yieldSource0), address(yieldSource1)),
            address(hook)
        );

        (key,) = initPool(currency0, currency1, IHooks(address(hook)), fee, SQRT_PRICE_1_1);
        (noHookKey,) = initPool(currency0, currency1, IHooks(address(0)), fee, SQRT_PRICE_1_1);

        vm.label(Currency.unwrap(currency0), "currency0");
        vm.label(Currency.unwrap(currency1), "currency1");

        IERC20(Currency.unwrap(currency0)).approve(address(hook), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(hook), type(uint256).max);

        // fund and get approval from lp1 and lp2
        deal((Currency.unwrap(currency0)), lp1, 1e18);
        deal((Currency.unwrap(currency0)), lp2, 1e18);
        deal((Currency.unwrap(currency1)), lp1, 1e18);
        deal((Currency.unwrap(currency1)), lp2, 1e18);

        _approveCurrencies([lp1, lp2], [currency0, currency1], [address(hook), address(swapRouter), address(manager)]);
    }

    function _approveCurrencies(address[2] memory approvers, Currency[2] memory currencies, address[3] memory spenders)
        internal
    {
        // make this contract approve `currencies` to `spenders`
        for (uint256 i = 0; i < currencies.length; i++) {
            for (uint256 j = 0; j < spenders.length; j++) {
                IERC20(Currency.unwrap(currencies[i])).approve(spenders[j], type(uint256).max);
            }
        }
        // make `approvers` approve `currencies` to `spenders`
        for (uint256 i = 0; i < approvers.length; i++) {
            vm.startPrank(approvers[i]);
            for (uint256 j = 0; j < currencies.length; j++) {
                for (uint256 k = 0; k < spenders.length; k++) {
                    IERC20(Currency.unwrap(currencies[j])).approve(spenders[k], type(uint256).max);
                }
            }
            vm.stopPrank();
        }
    }

    // Add Statefull/invariant fuzz that `getUsableLiquidityFromYieldSources` should always return the same value
    // before and after calling `collectAccruedYields` when the yields have diverged, to demostrate that it doesn't affect it.

    // Property: On first liquidity deposit before ratio divergences, the entire liquidity should be usable
    // assertEq(hook.getMaximumLiquidityFromYieldSources(), liquidity, "usable liquidity != liquidity");

    function testFuzz_add_remove_inflationProtection_keeps_one_unit(uint128 liquidity) public {
        liquidity = uint128(bound(liquidity, 1e12, 1e20)); // Reasonable liquidity range

        BalanceDelta addDelta = hook.addReHypothecatedLiquidity(liquidity);

        uint256 lpMaxWithdraw = hook.maxWithdraw(address(this));
        assertEq(lpMaxWithdraw, liquidity - 1, "lpMaxWithdraw != liquidity - 1");

        BalanceDelta removeDelta = hook.removeReHypothecatedLiquidity(lpMaxWithdraw.toUint128());
        assertEq(-addDelta.amount0() - 1, removeDelta.amount0(), "added - 1 != removed");
        assertEq(-addDelta.amount1() - 1, removeDelta.amount1(), "added - 1 != removed");

        uint256 hookAmount0 = hook.getAmountInYieldSource(currency0);
        assertEq(hookAmount0, 1, "hook amount0 != 1");

        uint256 hookAmount1 = hook.getAmountInYieldSource(currency1);
        assertEq(hookAmount1, 1, "hook amount1 != 1");

        uint256 hookLiquidity = hook.totalAssets();
        assertEq(hookLiquidity, 1, "hook liquidity != 1");
    }

    uint256[] public fixturepercent = [1, 50, 100]; // Ensure fixture inclusion

    // function testFuzz_add_remove_sharesCalculation_singleLP(uint128 liquidity, uint256 percent) public {
    //     liquidity = uint128(bound(liquidity, 1e12, 1e20)); // Reasonable liquidity range
    //     percent = uint256(bound(percent, 1, 100)); // Reasonable percentage range

    //     uint256 lpPreviewedSharesToAdd = hook.previewDeposit(liquidity);
    //     BalanceDelta addDelta = hook.addReHypothecatedLiquidity(liquidity);
    //     (uint256 amount0Added, uint256 amount1Added) =
    //         ((-addDelta.amount0()).toUint256(), (-addDelta.amount1()).toUint256());

    //     uint256 lpSharesAfterAdding = hook.balanceOf(address(this));
    //     assertEq(lpSharesAfterAdding, lpPreviewedSharesToAdd, "lpSharesAdded != lpPreviewedSharesToAdd");

    //     uint256 totalSharesAfterAdding = hook.totalSupply();
    //     assertEq(totalSharesAfterAdding, lpSharesAfterAdding, "totalSharesAfterAdding != lpSharesAdded");

    //     uint256 lpMaxWithdrawAfterAdding = hook.maxWithdraw(address(this));
    //     assertApproxEqAbs(lpMaxWithdrawAfterAdding, liquidity, 1, "lpMaxWithdrawAfterAdding !~= liquidity");

    //     uint256 liquidityToRemove = lpMaxWithdrawAfterAdding * percent / 100;

    //     uint256 lpPreviewedSharesToBurn = hook.previewWithdraw(liquidityToRemove.toUint128());
    //     BalanceDelta removeDelta = hook.removeReHypothecatedLiquidity(liquidityToRemove.toUint128());
    //     (uint256 amount0Removed, uint256 amount1Removed) =
    //         (removeDelta.amount0().toUint256(), removeDelta.amount1().toUint256());

    //     uint256 lpSharesAfterBurning = hook.balanceOf(address(this));
    //     uint256 lpSharesBurned = lpSharesAfterAdding - lpSharesAfterBurning;
    //     assertEq(lpSharesBurned, lpPreviewedSharesToBurn, "lpSharesBurned != lpPreviewedSharesToBurn");

    //     assertApproxEqAbs(
    //         lpSharesBurned, lpSharesAfterAdding * percent / 100, 1, "lpSharesBurned !~= percent% of lpSharesAdded"
    //     );
    //     assertApproxEqAbs(amount0Removed, amount0Added * percent / 100, 2, "removed0 !~= percent% of added0");
    //     assertApproxEqAbs(amount1Removed, amount1Added * percent / 100, 2, "removed1 !~= percent% of added1");

    //     uint256 totalSharesAfterRemoving = hook.totalSupply();
    //     assertApproxEqAbs(
    //         totalSharesAfterRemoving, lpSharesAfterBurning, 1, "totalSharesAfterRemoving !~= lpSharesAfterBurning"
    //     );

    //     uint256 lpMaxWithdrawAfterRemoving = hook.maxWithdraw(address(this));
    //     assertApproxEqAbs(
    //         lpMaxWithdrawAfterRemoving,
    //         lpMaxWithdrawAfterAdding - liquidityToRemove,
    //         1,
    //         "lpMaxWithdrawAfterRemoving !~= lpMaxWithdrawAfterAdding - liquidityToRemove"
    //     );
    // }

    function testFuzz_addRehypothecatedLiquidity_singleLP(uint128 liquidity) public {
        liquidity = uint128(bound(liquidity, 1e12, 1e20));

        uint256 lpAmount0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 lpAmount1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        uint256 amount0InYieldSource0Before = hook.getAmountInYieldSource(currency0);
        uint256 amount1InYieldSource1Before = hook.getAmountInYieldSource(currency1);

        uint256 previewedShares = hook.previewDeposit(liquidity);
        assertEq(previewedShares, liquidity, "previewed shares != liquidity");

        BalanceDelta delta = hook.addReHypothecatedLiquidity(liquidity);

        (uint256 amount0, uint256 amount1) = hook.getAmountsForLiquidity(liquidity);

        assertEq((-delta.amount0()).toUint256(), amount0, "Delta.amount0() != amount0");
        assertEq((-delta.amount1()).toUint256(), amount1, "Delta.amount1() != amount1");

        uint256 lpAmount0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 lpAmount1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        assertEq(lpAmount0After, lpAmount0Before - amount0, "lpAmount0After != lpAmount0Before - amount0");
        assertEq(lpAmount1After, lpAmount1Before - amount1, "lpAmount1After != lpAmount1Before - amount1");

        uint256 amount0InYieldSource0After = hook.getAmountInYieldSource(currency0);
        uint256 amount1InYieldSource1After = hook.getAmountInYieldSource(currency1);
        assertEq(
            amount0InYieldSource0After,
            amount0InYieldSource0Before + amount0,
            "amount0InYieldSource0After != amount0InYieldSource0Before + amount0"
        );
        assertEq(
            amount1InYieldSource1After,
            amount1InYieldSource1Before + amount1,
            "amount1InYieldSource1After != amount1InYieldSource1Before + amount1"
        );

        uint256 obtainedShares = hook.balanceOf(address(this));
        assertEq(obtainedShares, previewedShares, "obtained shares != previewed shares");
        assertEq(obtainedShares, hook.totalSupply(), "obtained shares != total supply");
    }

    function testFuzz_removeRehypothecatedLiquidity_singleLP(uint128 liquidity) public {
        liquidity = uint128(bound(liquidity, 1e12, 1e20));

        hook.addReHypothecatedLiquidity(liquidity);

        uint256 lpAmount0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 lpAmount1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        uint256 amount0InYieldSource0Before = hook.getAmountInYieldSource(currency0);
        uint256 amount1InYieldSource1Before = hook.getAmountInYieldSource(currency1);

        (uint256 amount0, uint256 amount1) = hook.getAmountsForLiquidity(liquidity);

        uint256 liquidityToRemove = hook.maxWithdraw(address(this));

        BalanceDelta delta = hook.removeReHypothecatedLiquidity(liquidityToRemove.toUint128());

        assertEq((-delta.amount0()).toUint256(), amount0, "Delta.amount0() !~= amount0");
        assertEq((-delta.amount1()).toUint256(), amount1, "Delta.amount1() !~= amount1");

        uint256 lpAmount0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 lpAmount1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        assertApproxEqAbs(lpAmount0After, lpAmount0Before + amount0, 1, "lpAmount0After !~= lpAmount0Before + amount0");
        assertApproxEqAbs(lpAmount1After, lpAmount1Before + amount1, 1, "lpAmount1After !~= lpAmount1Before + amount1");

        uint256 amount0InYieldSource0After = hook.getAmountInYieldSource(currency0);
        uint256 amount1InYieldSource1After = hook.getAmountInYieldSource(currency1);
        assertApproxEqAbs(
            amount0InYieldSource0After,
            amount0InYieldSource0Before - amount0,
            1,
            "amount0InYieldSource0After !~= amount0InYieldSource0Before + amount0"
        );
        assertApproxEqAbs(
            amount1InYieldSource1After,
            amount1InYieldSource1Before - amount1,
            1,
            "amount1InYieldSource1After !~= amount1InYieldSource1Before + amount1"
        );

        uint256 heldShares = hook.balanceOf(address(this));
        assertEq(heldShares, 0, "Held shares != 0");
        assertEq(hook.totalSupply(), 0, "total shares != 0");
    }

    // Compare adding, swapping and removing between hooked and unhooked pool.
    function test_differential_add_swap_remove_SingleLP() public {
        // liquidity = uint128(bound(liquidity, 1e12, 1e20));
        uint128 liquidity = 1e18;
        int256 amountToSwap = 1e14;

        // -- Add liquidity --

        // Hooked
        BalanceDelta hookedAddDelta = hook.addReHypothecatedLiquidity(liquidity);
        // Unhooked
        BalanceDelta noHookAddDelta =
            modifyPoolLiquidity(noHookKey, hook.getTickLower(), hook.getTickUpper(), int256(uint256(liquidity)), 0);

        assertApproxEqAbs(hookedAddDelta, noHookAddDelta, 1, "hookedAddDelta !~= noHookAddDelta");

        // -- Swap liquidity --

        // Hooked
        vm.startPrank(lp1);
        BalanceDelta hookedSwapDelta = swap(key, true, amountToSwap, ZERO_BYTES);

        // Unhooked
        BalanceDelta noHookSwapDelta = swap(noHookKey, true, amountToSwap, ZERO_BYTES);
        vm.stopPrank();

        assertApproxEqAbs(hookedSwapDelta, noHookSwapDelta, 1, "hookedSwapDelta !~= noHookSwapDelta");

        // -- Remove liquidity --

        uint256 liquidityToRemove = hook.maxWithdraw(address(this));

        // Hooked
        BalanceDelta hookedRemoveDelta = hook.removeReHypothecatedLiquidity(liquidityToRemove.toUint128());
        // Unhooked
        BalanceDelta noHookRemoveDelta =
            modifyPoolLiquidity(noHookKey, hook.getTickLower(), hook.getTickUpper(), -liquidityToRemove.toInt256(), 0);

        assertApproxEqAbs(hookedRemoveDelta, noHookRemoveDelta, 1, "hookedRemoveDelta !~= noHookRemoveDelta");
    }
}
// function test_already_initialized_reverts() public {
//     vm.expectRevert();
//     initPool(currency0, currency1, IHooks(address(hook)), fee, SQRT_PRICE_1_1);
// }

// function test_full_cycle() public {
//     uint128 liquidity = 1e15;
//     BalanceDelta delta = hook.addReHypothecatedLiquidity(liquidity);

//     assertEq(
//         IERC4626(address(yieldSource0)).balanceOf(address(hook)),
//         uint256(liquidity),
//         "YieldSource0 balance should be the same as the liquidity"
//     );
//     assertEq(
//         IERC4626(address(yieldSource1)).balanceOf(address(hook)),
//         uint256(liquidity),
//         "YieldSource1 balance should be the same as the liquidity"
//     );

//     assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity should be 0");

//     assertEq(hook.balanceOf(address(this)), liquidity, "Hook balance should be the same as the liquidity");

//     // add rehypothecated liquidity should be equal to modifyPoolLiquidity with a pool with the same state
//     BalanceDelta expectedDelta =
//         modifyPoolLiquidity(noHookKey, hook.getTickLower(), hook.getTickUpper(), int256(uint256(liquidity)), 0);
//     assertEq(delta, expectedDelta, "Delta should be equal");

//     BalanceDelta swapDelta = swap(key, false, 1e14, ZERO_BYTES);
//     BalanceDelta noHookSwapDelta = swap(noHookKey, false, 1e14, ZERO_BYTES);

//     assertEq(swapDelta, noHookSwapDelta, "Swap delta should be equal");
//     assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity should be 0");

//     assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(hook)), 0, "Currency0 balance should be 0");
//     assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(hook)), 0, "Currency1 balance should be 0");

//     assertApproxEqAbs(
//         IERC4626(address(yieldSource0)).balanceOf(address(hook)),
//         uint256(liquidity - uint128(swapDelta.amount0())),
//         2,
//         "YieldSource0 balance should go to user"
//     );
//     assertApproxEqAbs(
//         IERC4626(address(yieldSource1)).balanceOf(address(hook)),
//         uint256(uint128(int128(liquidity) - swapDelta.amount1())),
//         2,
//         "YieldSource1 balance should go to user"
//     );

//     delta = hook.removeReHypothecatedLiquidity(address(this));

//     expectedDelta =
//         modifyPoolLiquidity(noHookKey, hook.getTickLower(), hook.getTickUpper(), int256(-int128(liquidity)), 0);

//     assertEq(delta, expectedDelta, "Delta should be equal");

//     assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity should be 0");

//     assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(hook)), 0, "Currency0 balance should be 0");
//     assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(hook)), 0, "Currency1 balance should be 0");

//     assertEq(IERC4626(address(yieldSource0)).balanceOf(address(hook)), 0, "YieldSource0 balance should be 0");
//     assertEq(IERC4626(address(yieldSource1)).balanceOf(address(hook)), 0, "YieldSource1 balance should be 0");

//     assertEq(hook.balanceOf(address(this)), 0, "Hook balance should be 0");
// }

// function test_swap_with_increased_shares() public {
//     uint128 liquidity = 1e15;
//     BalanceDelta delta = hook.addReHypothecatedLiquidity(liquidity);

//     IERC20(Currency.unwrap(currency0)).transfer(address(yieldSource0), 1e14); // 10% increase on currency0
//     IERC20(Currency.unwrap(currency1)).transfer(address(yieldSource1), 1e14); // 10% increase on currency1

//     assertEq(
//         IERC4626(address(yieldSource0)).balanceOf(address(hook)),
//         uint256(liquidity),
//         "YieldSource0 balance should be the same as the liquidity"
//     );
//     assertEq(
//         IERC4626(address(yieldSource1)).balanceOf(address(hook)),
//         uint256(liquidity),
//         "YieldSource1 balance should be the same as the liquidity"
//     );

//     assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity should be 0");

//     assertEq(hook.balanceOf(address(this)), liquidity, "Hook balance should be the same as the liquidity");

//     // add rehypothecated liquidity should be equal to modifyPoolLiquidity with a pool with the same state
//     BalanceDelta expectedDelta =
//         modifyPoolLiquidity(noHookKey, hook.getTickLower(), hook.getTickUpper(), int256(uint256(liquidity)), 0);
//     assertEq(delta, expectedDelta, "Delta should be equal");

//     assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity should be 0");

//     assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(hook)), 0, "Currency0 balance should be 0");
//     assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(hook)), 0, "Currency1 balance should be 0");

//     delta = hook.removeReHypothecatedLiquidity(address(this));

//     expectedDelta =
//         modifyPoolLiquidity(noHookKey, hook.getTickLower(), hook.getTickUpper(), int256(-int128(liquidity)), 0);

//     assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity should be 0");

//     assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(hook)), 0, "Currency0 balance should be 0");
//     assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(hook)), 0, "Currency1 balance should be 0");

//     assertEq(IERC4626(address(yieldSource0)).balanceOf(address(hook)), 0, "YieldSource0 balance should be 0");
//     assertEq(IERC4626(address(yieldSource1)).balanceOf(address(hook)), 0, "YieldSource1 balance should be 0");

//     assertEq(hook.balanceOf(address(this)), 0, "Hook balance should be 0");
// }

// function test_add_rehypothecated_liquidity_zero_liquidity_reverts() public {
//     vm.expectRevert(ReHypothecationHook.ZeroLiquidity.selector);
//     hook.addReHypothecatedLiquidity(0);
// }

// function test_add_rehypothecated_liquidity_uninitialized_pool_key_reverts() public {
//     ReHypothecationERC4626Mock newHook = ReHypothecationERC4626Mock(
//         address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) + 2 ** 96)
//     );

//     deployCodeTo(
//         "src/mocks/ReHypothecationMock.sol:ReHypothecationMock",
//         abi.encode(manager, address(yieldSource0), address(yieldSource1)),
//         address(newHook)
//     );
//     vm.expectRevert(ReHypothecationHook.NotInitialized.selector);
//     newHook.addReHypothecatedLiquidity(1e15);
// }

// function test_add_rehypothecated_liquidity_msg_value_reverts() public {
//     vm.expectRevert(ReHypothecationHook.InvalidMsgValue.selector);
//     hook.addReHypothecatedLiquidity{value: 1e5}(1e15);
// }

// function test_remove_rehypothecated_liquidity_zero_liquidity_reverts() public {
//     vm.expectRevert(ReHypothecationHook.ZeroLiquidity.selector);
//     hook.removeReHypothecatedLiquidity(address(this));
// }

// function test_remove_rehypothecated_liquidity_uninitialized_pool_key_reverts() public {
//     ReHypothecationMock newHook = ReHypothecationMock(
//         address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) + 2 ** 96)
//     );

//     deployCodeTo(
//         "src/mocks/ReHypothecationMock.sol:ReHypothecationMock",
//         abi.encode(manager, address(yieldSource0), address(yieldSource1)),
//         address(newHook)
//     );
//     vm.expectRevert(ReHypothecationHook.NotInitialized.selector);
//     newHook.removeReHypothecatedLiquidity(address(this));
// }

// function test_add_rehypothecated_liquidity_invalid_currency_reverts() public {
//     ReHypothecationMock newHook = ReHypothecationMock(
//         address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) + 2 ** 96)
//     );

//     deployCodeTo(
//         "src/mocks/ReHypothecationMock.sol:ReHypothecationMock",
//         abi.encode(manager, address(yieldSource0), address(yieldSource1)),
//         address(newHook)
//     );

//     initPool(Currency.wrap(address(0)), currency1, IHooks(address(newHook)), fee, SQRT_PRICE_1_1);

//     IERC20(Currency.unwrap(currency1)).approve(address(newHook), type(uint256).max);

//     vm.expectRevert(ReHypothecationHook.UnsupportedCurrency.selector);
//     newHook.addReHypothecatedLiquidity{value: 1e15}(1e15);
// }

// function test_add_rehypothecated_liquidity_native_reverts() public {
//     ReHypothecationMock newHook = ReHypothecationMock(
//         address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) + 2 ** 96)
//     );

//     deployCodeTo(
//         "src/mocks/ReHypothecationMock.sol:ReHypothecationMock",
//         abi.encode(manager, address(yieldSource0), address(yieldSource1)),
//         address(newHook)
//     );

//     initPool(Currency.wrap(address(0)), currency1, IHooks(address(newHook)), fee, SQRT_PRICE_1_1);

//     vm.expectRevert(ReHypothecationHook.InvalidMsgValue.selector);
//     newHook.addReHypothecatedLiquidity{value: 1e14}(1e15);
// }

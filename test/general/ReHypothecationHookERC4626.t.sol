// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// // External imports
// import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
// import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
// import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
// import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
// import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
// import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
// import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
// import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
// import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
// import {BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
// // Internal imports
// import {ReHypothecationHook} from "../../src/general/ReHypothecationHook.sol";
// import {ReHypothecationERC4626Mock, ERC4626YieldSourceMock} from "../../src/mocks/ReHypothecationERC4626Mock.sol";
// import {HookTest} from "../../test/utils/HookTest.sol";
// import {BalanceDeltaAssertions} from "../../test/utils/BalanceDeltaAssertions.sol";
// import {console} from "forge-std/console.sol";

// contract ReHypothecationHookERC4626Test is HookTest, BalanceDeltaAssertions {
//     using StateLibrary for IPoolManager;
//     using SafeCast for *;
//     using Math for *;

//     ReHypothecationERC4626Mock hook;

//     IERC4626 yieldSource0;
//     IERC4626 yieldSource1;

//     PoolKey noHookKey;

//     address lp1 = makeAddr("lp1");
//     address lp2 = makeAddr("lp2");

//     uint24 fee = 1000; // 0.1%

//     function setUp() public {
//         deployFreshManagerAndRouters();
//         deployMintAndApprove2Currencies();

//         yieldSource0 = IERC4626(new ERC4626YieldSourceMock(IERC20(Currency.unwrap(currency0)), "Yield Source 0", "Y0"));
//         yieldSource1 = IERC4626(new ERC4626YieldSourceMock(IERC20(Currency.unwrap(currency1)), "Yield Source 1", "Y1"));

//         hook = ReHypothecationERC4626Mock(
//             address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG))
//         );
//         deployCodeTo(
//             "src/mocks/ReHypothecationERC4626Mock.sol:ReHypothecationERC4626Mock",
//             abi.encode(manager, address(yieldSource0), address(yieldSource1)),
//             address(hook)
//         );

//         (key,) = initPool(currency0, currency1, IHooks(address(hook)), fee, SQRT_PRICE_1_1);
//         (noHookKey,) = initPool(currency0, currency1, IHooks(address(0)), fee, SQRT_PRICE_1_1);

//         vm.label(Currency.unwrap(currency0), "currency0");
//         vm.label(Currency.unwrap(currency1), "currency1");

//         IERC20(Currency.unwrap(currency0)).approve(address(hook), type(uint256).max);
//         IERC20(Currency.unwrap(currency1)).approve(address(hook), type(uint256).max);

//         // fund and get approval from lp1 and lp2
//         deal((Currency.unwrap(currency0)), lp1, 1e18);
//         deal((Currency.unwrap(currency0)), lp2, 1e18);
//         deal((Currency.unwrap(currency1)), lp1, 1e18);
//         deal((Currency.unwrap(currency1)), lp2, 1e18);

//         vm.startPrank(lp1);
//         IERC20(Currency.unwrap(currency0)).approve(address(hook), type(uint256).max);
//         IERC20(Currency.unwrap(currency1)).approve(address(hook), type(uint256).max);
//         vm.stopPrank();

//         vm.startPrank(lp2);
//         IERC20(Currency.unwrap(currency0)).approve(address(hook), type(uint256).max);
//         IERC20(Currency.unwrap(currency1)).approve(address(hook), type(uint256).max);
//         vm.stopPrank();
//     }

//     // Note that `getLiquidityForAmounts` generates small rounding errors
//     function testFuzz_getLiquidityForAmounts(uint256 amount) public view {
//         amount = uint256(bound(amount, 1e12, 1e20));
//         uint128 liquidity = hook.getLiquidityForAmounts(amount, amount);
//         assertApproxEqAbs(liquidity, amount, 10, "liquidity != amount");
//     }

//     // Note that `getAmountsForLiquidity` generates small rounding errors
//     function testFuzz_getAmountsForLiquidity(uint128 liquidity) public view {
//         liquidity = uint128(bound(liquidity, 1e12, 1e20));
//         (uint256 amount0, uint256 amount1) = hook.getAmountsForLiquidity(liquidity);
//         assertApproxEqAbs(amount0, liquidity, 10, "amount0 != liquidity");
//         assertApproxEqAbs(amount1, liquidity, 10, "amount1 != liquidity");
//     }

//     // Add Statefull fuzz that `getUsableLiquidityFromYieldSources` should always return the same value
//     // before and after calling `collectAccruedYields`, to demostrate that it doesn't affect it.

//     function testFuzz_shareCalculationConsistency(uint128 liquidity) public {
//         liquidity = uint128(bound(liquidity, 1e12, 1e20)); // Reasonable liquidity range

//         // First deposit to establish baseline
//         uint256 previewedShares = hook.previewDeposit(liquidity);
//         hook.addReHypothecatedLiquidity(liquidity);
//         uint256 actualShares = hook.balanceOf(address(this));

//         // Property: Previewed shares should match actual shares
//         assertEq(actualShares, previewedShares, "preview != actual shares");

//         // Property: On first liquidity deposit, the entire liquidity should be usable
//         assertEq(hook.getUsableLiquidityFromYieldSources(), liquidity, "usable liquidity != liquidity");

//         // Now test withdrawal
//         uint256 previewedBurn = hook.previewWithdraw(liquidity);

//         // Property: Should not try to burn more shares than user has
//         assertLe(previewedBurn, actualShares, "trying to burn more shares than owned");

//         // Property: Preview should be close to actual shares (within rounding)
//         assertApproxEqAbs(previewedBurn, actualShares, 10, "burn preview too different from actual");
//     }

//     function test_addRehypothecatedLiquidity_singleLP() public {
//         uint128 liquidity = 1e15;

//         uint256 previewedShares = hook.previewDeposit(liquidity);
//         assertEq(previewedShares, liquidity, "previewed shares != liquidity");

//         BalanceDelta delta = hook.addReHypothecatedLiquidity(liquidity);

//         (uint256 amount0, uint256 amount1) = hook.getAmountsForLiquidity(liquidity);

//         assertEq(delta.amount0().toUint256(), amount0, "Delta.amount0() != amount0");
//         assertEq(delta.amount1().toUint256(), amount1, "Delta.amount1() != amount1");

//         uint256 yieldSource0Shares = yieldSource0.balanceOf(address(hook));
//         uint256 yieldSource0Assets = yieldSource0.convertToAssets(yieldSource0Shares);
//         assertEq(yieldSource0Assets, amount0, "YieldSource0 balance != amount0");

//         uint256 yieldSource1Shares = yieldSource1.balanceOf(address(hook));
//         uint256 yieldSource1Assets = yieldSource1.convertToAssets(yieldSource1Shares);
//         assertEq(yieldSource1Assets, amount1, "YieldSource1 balance != amount1");

//         uint256 obtainedShares = hook.balanceOf(address(this));
//         assertEq(obtainedShares, previewedShares, "obtained shares != previewed shares");
//         assertEq(obtainedShares, hook.totalSupply(), "obtained shares != total supply");
//     }

//     function test_removeRehypothecatedLiquidity_singleLP() public {
//         uint128 liquidity = 1e15;

//         uint256 usableLiquidityBeforeAdding = hook.getUsableLiquidityFromYieldSources();
//         console.log("Usable liquidity before adding liquidity:", usableLiquidityBeforeAdding);

//         hook.addReHypothecatedLiquidity(liquidity);

//         uint256 totalSharesBefore = hook.totalSupply();
//         console.log("Shares before removal:", hook.balanceOf(address(this)));
//         console.log("Total supply:", hook.totalSupply());

//         uint256 yieldSource0SharesBefore = yieldSource0.balanceOf(address(hook));
//         uint256 yieldSource0AssetsBefore = yieldSource0.convertToAssets(yieldSource0SharesBefore);
//         console.log("YieldSource0 assets before:", yieldSource0AssetsBefore);

//         uint256 yieldSource1SharesBefore = yieldSource1.balanceOf(address(hook));
//         uint256 yieldSource1AssetsBefore = yieldSource1.convertToAssets(yieldSource1SharesBefore);
//         console.log("YieldSource1 assets before:", yieldSource1AssetsBefore);

//         uint256 usableLiquidityBefore = hook.getUsableLiquidityFromYieldSources();
//         console.log("Usable liquidity before:", usableLiquidityBefore);

//         uint256 multiplicationFirst = liquidity * totalSharesBefore;
//         console.log("Multiplication first:", multiplicationFirst);

//         uint256 divisionSecond = multiplicationFirst / usableLiquidityBefore;
//         console.log("Division second:", divisionSecond);

//         uint256 manualPreviewBurn =
//          liquidity.mulDiv(totalSharesBefore, usableLiquidityBefore);
//         console.log("Manual preview burn:", manualPreviewBurn);

//         uint256 completeManualPreviewBurn =
//                  liquidity.mulDiv(totalSharesBefore + 1, usableLiquidityBefore + 1);
//         console.log("Complete manual preview burn:", completeManualPreviewBurn);

//         uint256 previewedBurn = hook.previewWithdraw(liquidity);
//         console.log("Previewed burn:", previewedBurn);

//         assertEq(previewedBurn, totalSharesBefore, "previewed burn != total shares before");

//         hook.removeReHypothecatedLiquidity(liquidity);

//         uint256 yieldSource0Shares = yieldSource0.balanceOf(address(hook));
//         uint256 yieldSource0Assets = yieldSource0.convertToAssets(yieldSource0Shares);
//         assertEq(yieldSource0Shares, 0, "YieldSource0 shares != 0");
//         assertEq(yieldSource0Assets, 0, "YieldSource0 assets != 0");

//         uint256 yieldSource1Shares = yieldSource1.balanceOf(address(hook));
//         uint256 yieldSource1Assets = yieldSource1.convertToAssets(yieldSource1Shares);
//         assertEq(yieldSource1Shares, 0, "YieldSource1 shares != 0");
//         assertEq(yieldSource1Assets, 0, "YieldSource1 assets != 0");

//         uint256 heldShares = hook.balanceOf(address(this));
//         assertEq(heldShares, 0, "Held shares != 0");
//         assertEq(hook.totalSupply(), 0, "total shares != 0");
//     }

//     // function test_already_initialized_reverts() public {
//     //     vm.expectRevert();
//     //     initPool(currency0, currency1, IHooks(address(hook)), fee, SQRT_PRICE_1_1);
//     // }

//     // function test_full_cycle() public {
//     //     uint128 liquidity = 1e15;
//     //     BalanceDelta delta = hook.addReHypothecatedLiquidity(liquidity);

//     //     assertEq(
//     //         IERC4626(address(yieldSource0)).balanceOf(address(hook)),
//     //         uint256(liquidity),
//     //         "YieldSource0 balance should be the same as the liquidity"
//     //     );
//     //     assertEq(
//     //         IERC4626(address(yieldSource1)).balanceOf(address(hook)),
//     //         uint256(liquidity),
//     //         "YieldSource1 balance should be the same as the liquidity"
//     //     );

//     //     assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity should be 0");

//     //     assertEq(hook.balanceOf(address(this)), liquidity, "Hook balance should be the same as the liquidity");

//     //     // add rehypothecated liquidity should be equal to modifyPoolLiquidity with a pool with the same state
//     //     BalanceDelta expectedDelta =
//     //         modifyPoolLiquidity(noHookKey, hook.getTickLower(), hook.getTickUpper(), int256(uint256(liquidity)), 0);
//     //     assertEq(delta, expectedDelta, "Delta should be equal");

//     //     BalanceDelta swapDelta = swap(key, false, 1e14, ZERO_BYTES);
//     //     BalanceDelta noHookSwapDelta = swap(noHookKey, false, 1e14, ZERO_BYTES);

//     //     assertEq(swapDelta, noHookSwapDelta, "Swap delta should be equal");
//     //     assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity should be 0");

//     //     assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(hook)), 0, "Currency0 balance should be 0");
//     //     assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(hook)), 0, "Currency1 balance should be 0");

//     //     assertApproxEqAbs(
//     //         IERC4626(address(yieldSource0)).balanceOf(address(hook)),
//     //         uint256(liquidity - uint128(swapDelta.amount0())),
//     //         2,
//     //         "YieldSource0 balance should go to user"
//     //     );
//     //     assertApproxEqAbs(
//     //         IERC4626(address(yieldSource1)).balanceOf(address(hook)),
//     //         uint256(uint128(int128(liquidity) - swapDelta.amount1())),
//     //         2,
//     //         "YieldSource1 balance should go to user"
//     //     );

//     //     delta = hook.removeReHypothecatedLiquidity(address(this));

//     //     expectedDelta =
//     //         modifyPoolLiquidity(noHookKey, hook.getTickLower(), hook.getTickUpper(), int256(-int128(liquidity)), 0);

//     //     assertEq(delta, expectedDelta, "Delta should be equal");

//     //     assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity should be 0");

//     //     assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(hook)), 0, "Currency0 balance should be 0");
//     //     assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(hook)), 0, "Currency1 balance should be 0");

//     //     assertEq(IERC4626(address(yieldSource0)).balanceOf(address(hook)), 0, "YieldSource0 balance should be 0");
//     //     assertEq(IERC4626(address(yieldSource1)).balanceOf(address(hook)), 0, "YieldSource1 balance should be 0");

//     //     assertEq(hook.balanceOf(address(this)), 0, "Hook balance should be 0");
//     // }

//     // function test_swap_with_increased_shares() public {
//     //     uint128 liquidity = 1e15;
//     //     BalanceDelta delta = hook.addReHypothecatedLiquidity(liquidity);

//     //     IERC20(Currency.unwrap(currency0)).transfer(address(yieldSource0), 1e14); // 10% increase on currency0
//     //     IERC20(Currency.unwrap(currency1)).transfer(address(yieldSource1), 1e14); // 10% increase on currency1

//     //     assertEq(
//     //         IERC4626(address(yieldSource0)).balanceOf(address(hook)),
//     //         uint256(liquidity),
//     //         "YieldSource0 balance should be the same as the liquidity"
//     //     );
//     //     assertEq(
//     //         IERC4626(address(yieldSource1)).balanceOf(address(hook)),
//     //         uint256(liquidity),
//     //         "YieldSource1 balance should be the same as the liquidity"
//     //     );

//     //     assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity should be 0");

//     //     assertEq(hook.balanceOf(address(this)), liquidity, "Hook balance should be the same as the liquidity");

//     //     // add rehypothecated liquidity should be equal to modifyPoolLiquidity with a pool with the same state
//     //     BalanceDelta expectedDelta =
//     //         modifyPoolLiquidity(noHookKey, hook.getTickLower(), hook.getTickUpper(), int256(uint256(liquidity)), 0);
//     //     assertEq(delta, expectedDelta, "Delta should be equal");

//     //     assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity should be 0");

//     //     assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(hook)), 0, "Currency0 balance should be 0");
//     //     assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(hook)), 0, "Currency1 balance should be 0");

//     //     delta = hook.removeReHypothecatedLiquidity(address(this));

//     //     expectedDelta =
//     //         modifyPoolLiquidity(noHookKey, hook.getTickLower(), hook.getTickUpper(), int256(-int128(liquidity)), 0);

//     //     assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity should be 0");

//     //     assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(hook)), 0, "Currency0 balance should be 0");
//     //     assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(hook)), 0, "Currency1 balance should be 0");

//     //     assertEq(IERC4626(address(yieldSource0)).balanceOf(address(hook)), 0, "YieldSource0 balance should be 0");
//     //     assertEq(IERC4626(address(yieldSource1)).balanceOf(address(hook)), 0, "YieldSource1 balance should be 0");

//     //     assertEq(hook.balanceOf(address(this)), 0, "Hook balance should be 0");
//     // }

//     // function test_add_rehypothecated_liquidity_zero_liquidity_reverts() public {
//     //     vm.expectRevert(ReHypothecationHook.ZeroLiquidity.selector);
//     //     hook.addReHypothecatedLiquidity(0);
//     // }

//     // function test_add_rehypothecated_liquidity_uninitialized_pool_key_reverts() public {
//     //     ReHypothecationERC4626Mock newHook = ReHypothecationERC4626Mock(
//     //         address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) + 2 ** 96)
//     //     );

//     //     deployCodeTo(
//     //         "src/mocks/ReHypothecationMock.sol:ReHypothecationMock",
//     //         abi.encode(manager, address(yieldSource0), address(yieldSource1)),
//     //         address(newHook)
//     //     );
//     //     vm.expectRevert(ReHypothecationHook.NotInitialized.selector);
//     //     newHook.addReHypothecatedLiquidity(1e15);
//     // }

//     // function test_add_rehypothecated_liquidity_msg_value_reverts() public {
//     //     vm.expectRevert(ReHypothecationHook.InvalidMsgValue.selector);
//     //     hook.addReHypothecatedLiquidity{value: 1e5}(1e15);
//     // }

//     // function test_remove_rehypothecated_liquidity_zero_liquidity_reverts() public {
//     //     vm.expectRevert(ReHypothecationHook.ZeroLiquidity.selector);
//     //     hook.removeReHypothecatedLiquidity(address(this));
//     // }

//     // function test_remove_rehypothecated_liquidity_uninitialized_pool_key_reverts() public {
//     //     ReHypothecationMock newHook = ReHypothecationMock(
//     //         address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) + 2 ** 96)
//     //     );

//     //     deployCodeTo(
//     //         "src/mocks/ReHypothecationMock.sol:ReHypothecationMock",
//     //         abi.encode(manager, address(yieldSource0), address(yieldSource1)),
//     //         address(newHook)
//     //     );
//     //     vm.expectRevert(ReHypothecationHook.NotInitialized.selector);
//     //     newHook.removeReHypothecatedLiquidity(address(this));
//     // }

//     // function test_add_rehypothecated_liquidity_invalid_currency_reverts() public {
//     //     ReHypothecationMock newHook = ReHypothecationMock(
//     //         address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) + 2 ** 96)
//     //     );

//     //     deployCodeTo(
//     //         "src/mocks/ReHypothecationMock.sol:ReHypothecationMock",
//     //         abi.encode(manager, address(yieldSource0), address(yieldSource1)),
//     //         address(newHook)
//     //     );

//     //     initPool(Currency.wrap(address(0)), currency1, IHooks(address(newHook)), fee, SQRT_PRICE_1_1);

//     //     IERC20(Currency.unwrap(currency1)).approve(address(newHook), type(uint256).max);

//     //     vm.expectRevert(ReHypothecationHook.UnsupportedCurrency.selector);
//     //     newHook.addReHypothecatedLiquidity{value: 1e15}(1e15);
//     // }

//     // function test_add_rehypothecated_liquidity_native_reverts() public {
//     //     ReHypothecationMock newHook = ReHypothecationMock(
//     //         address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) + 2 ** 96)
//     //     );

//     //     deployCodeTo(
//     //         "src/mocks/ReHypothecationMock.sol:ReHypothecationMock",
//     //         abi.encode(manager, address(yieldSource0), address(yieldSource1)),
//     //         address(newHook)
//     //     );

//     //     initPool(Currency.wrap(address(0)), currency1, IHooks(address(newHook)), fee, SQRT_PRICE_1_1);

//     //     vm.expectRevert(ReHypothecationHook.InvalidMsgValue.selector);
//     //     newHook.addReHypothecatedLiquidity{value: 1e14}(1e15);
//     // }
// }

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BalanceDeltaAssertions} from "../BalanceDeltaAssertions.sol";

contract BalanceDeltaAssertionsTest is Test, BalanceDeltaAssertions {
    BalanceDelta delta1;
    BalanceDelta delta2;
    BalanceDelta delta3;

    function setUp() public {
        delta1 = toBalanceDelta(100, 200);
        delta2 = toBalanceDelta(100, 200);
        delta3 = toBalanceDelta(150, 250);
    }

    // ========== assertEq Tests ==========

    function test_assertEq_success() public pure {
        BalanceDelta a = toBalanceDelta(100, 200);
        BalanceDelta b = toBalanceDelta(100, 200);
        
        // Should not revert
        assertEq(a, b);
    }

    function test_assertEq_withMessage_success() public pure {
        BalanceDelta a = toBalanceDelta(100, 200);
        BalanceDelta b = toBalanceDelta(100, 200);
        
        // Should not revert
        assertEq(a, b, "Deltas should be equal");
    }

    function test_assertEq_failure_amount0() public {
        BalanceDelta a = toBalanceDelta(100, 200);
        BalanceDelta b = toBalanceDelta(101, 200); // Different amount0
        
        vm.expectRevert();
        assertEq(a, b);
    }

    function test_assertEq_failure_amount1() public {
        BalanceDelta a = toBalanceDelta(100, 200);
        BalanceDelta b = toBalanceDelta(100, 201); // Different amount1
        
        vm.expectRevert();
        assertEq(a, b);
    }

    // ========== assertAproxEqAbs Tests ==========

    function test_assertAproxEqAbs_success() public pure {
        BalanceDelta a = toBalanceDelta(100, 200);
        BalanceDelta b = toBalanceDelta(102, 198);
        
        // Should not revert with tolerance of 5
        assertAproxEqAbs(a, b, 5);
    }

    function test_assertAproxEqAbs_withMessage_success() public pure {
        BalanceDelta a = toBalanceDelta(100, 200);
        BalanceDelta b = toBalanceDelta(102, 198);
        
        // Should not revert with tolerance of 5
        assertAproxEqAbs(a, b, 5, "Should be approximately equal");
    }

    function test_assertAproxEqAbs_failure() public {
        BalanceDelta a = toBalanceDelta(100, 200);
        BalanceDelta b = toBalanceDelta(110, 190); // Difference of 10
        
        vm.expectRevert();
        assertAproxEqAbs(a, b, 5); // Tolerance too small
    }

    function test_assertAproxEqAbs_exact_tolerance() public pure {
        BalanceDelta a = toBalanceDelta(100, 200);
        BalanceDelta b = toBalanceDelta(105, 195); // Difference of exactly 5
        
        // Should not revert with tolerance of 5
        assertAproxEqAbs(a, b, 5);
    }

    // ========== assertNotEq Tests ==========

    function test_assertNotEq_success_amount0() public pure {
        BalanceDelta a = toBalanceDelta(100, 200);
        BalanceDelta b = toBalanceDelta(101, 200); // Different amount0
        
        // Should not revert
        assertNotEq(a, b);
    }

    function test_assertNotEq_success_amount1() public pure {
        BalanceDelta a = toBalanceDelta(100, 200);
        BalanceDelta b = toBalanceDelta(100, 201); // Different amount1
        
        // Should not revert
        assertNotEq(a, b);
    }

    function test_assertNotEq_success_both() public pure {
        BalanceDelta a = toBalanceDelta(100, 200);
        BalanceDelta b = toBalanceDelta(101, 201); // Different both
        
        // Should not revert
        assertNotEq(a, b);
    }

    function test_assertNotEq_withMessage_success() public pure {
        BalanceDelta a = toBalanceDelta(100, 200);
        BalanceDelta b = toBalanceDelta(101, 200);
        
        // Should not revert
        assertNotEq(a, b, "Should be different");
    }

    function test_assertNotEq_failure() public {
        BalanceDelta a = toBalanceDelta(100, 200);
        BalanceDelta b = toBalanceDelta(100, 200); // Same values
        
        vm.expectRevert();
        assertNotEq(a, b);
    }

    // ========== assertGt Tests ==========

    function test_assertGt_success() public pure {
        BalanceDelta a = toBalanceDelta(101, 201);
        BalanceDelta b = toBalanceDelta(100, 200);
        
        // Should not revert
        assertGt(a, b);
    }

    function test_assertGt_withMessage_success() public pure {
        BalanceDelta a = toBalanceDelta(101, 201);
        BalanceDelta b = toBalanceDelta(100, 200);
        
        // Should not revert
        assertGt(a, b, "First should be greater");
    }

    function test_assertGt_failure_amount0() public {
        BalanceDelta a = toBalanceDelta(100, 201); // amount0 not greater
        BalanceDelta b = toBalanceDelta(100, 200);
        
        vm.expectRevert();
        assertGt(a, b);
    }

    function test_assertGt_failure_amount1() public {
        BalanceDelta a = toBalanceDelta(101, 200); // amount1 not greater
        BalanceDelta b = toBalanceDelta(100, 200);
        
        vm.expectRevert();
        assertGt(a, b);
    }

    // ========== assertEitherGt Tests ==========

    function test_assertEitherGt_success_amount0() public pure {
        BalanceDelta a = toBalanceDelta(101, 200); // Only amount0 greater
        BalanceDelta b = toBalanceDelta(100, 200);
        
        // Should not revert
        assertEitherGt(a, b);
    }

    function test_assertEitherGt_success_amount1() public pure {
        BalanceDelta a = toBalanceDelta(100, 201); // Only amount1 greater
        BalanceDelta b = toBalanceDelta(100, 200);
        
        // Should not revert
        assertEitherGt(a, b);
    }

    function test_assertEitherGt_success_both() public pure {
        BalanceDelta a = toBalanceDelta(101, 201); // Both greater
        BalanceDelta b = toBalanceDelta(100, 200);
        
        // Should not revert
        assertEitherGt(a, b);
    }

    function test_assertEitherGt_withMessage_success() public pure {
        BalanceDelta a = toBalanceDelta(101, 200);
        BalanceDelta b = toBalanceDelta(100, 200);
        
        // Should not revert
        assertEitherGt(a, b, "At least one should be greater");
    }

    function test_assertEitherGt_failure() public {
        BalanceDelta a = toBalanceDelta(100, 200); // Neither greater
        BalanceDelta b = toBalanceDelta(100, 200);
        
        vm.expectRevert();
        assertEitherGt(a, b);
    }

    // ========== assertLt Tests ==========

    function test_assertLt_success() public pure {
        BalanceDelta a = toBalanceDelta(99, 199);
        BalanceDelta b = toBalanceDelta(100, 200);
        
        // Should not revert
        assertLt(a, b);
    }

    function test_assertLt_withMessage_success() public pure {
        BalanceDelta a = toBalanceDelta(99, 199);
        BalanceDelta b = toBalanceDelta(100, 200);
        
        // Should not revert
        assertLt(a, b, "First should be less");
    }

    function test_assertLt_failure_amount0() public {
        BalanceDelta a = toBalanceDelta(100, 199); // amount0 not less
        BalanceDelta b = toBalanceDelta(100, 200);
        
        vm.expectRevert();
        assertLt(a, b);
    }

    function test_assertLt_failure_amount1() public {
        BalanceDelta a = toBalanceDelta(99, 200); // amount1 not less
        BalanceDelta b = toBalanceDelta(100, 200);
        
        vm.expectRevert();
        assertLt(a, b);
    }

    // ========== assertEitherLt Tests ==========

    function test_assertEitherLt_success_amount0() public pure {
        BalanceDelta a = toBalanceDelta(99, 200); // Only amount0 less
        BalanceDelta b = toBalanceDelta(100, 200);
        
        // Should not revert
        assertEitherLt(a, b);
    }

    function test_assertEitherLt_success_amount1() public pure {
        BalanceDelta a = toBalanceDelta(100, 199); // Only amount1 less
        BalanceDelta b = toBalanceDelta(100, 200);
        
        // Should not revert
        assertEitherLt(a, b);
    }

    function test_assertEitherLt_success_both() public pure {
        BalanceDelta a = toBalanceDelta(99, 199); // Both less
        BalanceDelta b = toBalanceDelta(100, 200);
        
        // Should not revert
        assertEitherLt(a, b);
    }

    function test_assertEitherLt_withMessage_success() public pure {
        BalanceDelta a = toBalanceDelta(99, 200);
        BalanceDelta b = toBalanceDelta(100, 200);
        
        // Should not revert
        assertEitherLt(a, b, "At least one should be less");
    }

    function test_assertEitherLt_failure() public {
        BalanceDelta a = toBalanceDelta(100, 200); // Neither less
        BalanceDelta b = toBalanceDelta(100, 200);
        
        vm.expectRevert();
        assertEitherLt(a, b);
    }

    // ========== Edge Cases ==========

    function test_negative_values() public pure {
        BalanceDelta a = toBalanceDelta(-100, -200);
        BalanceDelta b = toBalanceDelta(-100, -200);
        
        assertEq(a, b);
    }

    function test_mixed_positive_negative() public pure {
        BalanceDelta a = toBalanceDelta(-100, 200);
        BalanceDelta b = toBalanceDelta(100, -200);
        
        assertNotEq(a, b);
    }

    function test_zero_values() public pure {
        BalanceDelta a = toBalanceDelta(0, 0);
        BalanceDelta b = toBalanceDelta(0, 0);
        
        assertEq(a, b);
    }

    function test_large_values() public pure {
        BalanceDelta a = toBalanceDelta(type(int128).max, type(int128).max);
        BalanceDelta b = toBalanceDelta(type(int128).max, type(int128).max);
        
        assertEq(a, b);
    }

    // ========== Fuzz Tests ==========

    function testFuzz_assertEq(int128 amount0, int128 amount1) public pure {
        BalanceDelta a = toBalanceDelta(amount0, amount1);
        BalanceDelta b = toBalanceDelta(amount0, amount1);
        
        assertEq(a, b);
    }

    function testFuzz_assertNotEq(int128 amount0a, int128 amount1a, int128 amount0b, int128 amount1b) public {
        vm.assume(amount0a != amount0b || amount1a != amount1b);
        
        BalanceDelta a = toBalanceDelta(amount0a, amount1a);
        BalanceDelta b = toBalanceDelta(amount0b, amount1b);
        
        assertNotEq(a, b);
    }

    function testFuzz_assertAproxEqAbs(int128 amount0, int128 amount1, uint256 tolerance) public {
        tolerance = bound(tolerance, 0, type(uint128).max);
        
        BalanceDelta a = toBalanceDelta(amount0, amount1);
        BalanceDelta b = toBalanceDelta(amount0, amount1);
        
        // Same values should always pass
        assertAproxEqAbs(a, b, tolerance);
    }
}

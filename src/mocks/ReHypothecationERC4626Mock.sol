// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// External imports
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

// Internal imports
import {ReHypothecationHook} from "../general/ReHypothecationHook.sol";

/// @title ERC4626Mock
/// @notice A mock implementation of the ERC-4626 yield source.
contract ERC4626YieldSourceMock is ERC4626 {
    constructor(IERC20 token, string memory name, string memory symbol) ERC4626(token) ERC20(name, symbol) {}
}

/// @title ReHypothecationERC4626Mock
/// @notice A mock implementation of the ReHypothecationHook for ERC-4626 yield sources.
contract ReHypothecationERC4626Mock is ReHypothecationHook {
    using SafeERC20 for IERC20;

    address private _yieldSource0;
    address private _yieldSource1;

    /// @dev Error thrown when attempting to use an unsupported currency.
    error UnsupportedCurrency();

    constructor(IPoolManager poolManager_, address yieldSource0_, address yieldSource1_)
        ReHypothecationHook(poolManager_)
        ERC20("ReHypothecationMock", "RHM")
    {
        _yieldSource0 = yieldSource0_;
        _yieldSource1 = yieldSource1_;
    }

    /// @inheritdoc ReHypothecationHook
    function getCurrencyYieldSource(Currency currency) public view override returns (address) {
        PoolKey memory poolKey = getPoolKey();
        if (currency == poolKey.currency0) return _yieldSource0;
        if (currency == poolKey.currency1) return _yieldSource1;
        revert UnsupportedCurrency();
    }

    /// @inheritdoc ReHypothecationHook
    function _depositToYieldSource(Currency currency, uint256 amount) internal virtual override {
        // In this ERC4626 implementation, native currency is not supported.
        if (currency.isAddressZero()) revert UnsupportedCurrency();

        address yieldSource = getCurrencyYieldSource(currency);
        if (yieldSource == address(0)) revert UnsupportedCurrency();

        IERC20(Currency.unwrap(currency)).approve(address(yieldSource), amount);
        IERC4626(yieldSource).deposit(amount, address(this));
    }

    /// @inheritdoc ReHypothecationHook
    function _withdrawFromYieldSource(Currency currency, uint256 amount) internal virtual override {
        IERC4626 yieldSource = IERC4626(getCurrencyYieldSource(currency));
        if (address(yieldSource) == address(0)) revert UnsupportedCurrency();

        yieldSource.withdraw(amount, address(this), address(this));
    }

    /// @inheritdoc ReHypothecationHook
    function _getAmountInYieldSource(Currency currency) internal view virtual override returns (uint256 amount) {
        IERC4626 yieldSource = IERC4626(getCurrencyYieldSource(currency));
        uint256 yieldSourceShares = yieldSource.balanceOf(address(this));
        return yieldSource.convertToAssets(yieldSourceShares);
    }

    // Helpers for testing

    function getLiquidityForAmounts(uint256 amount0, uint256 amount1) public view returns (uint128 liquidity) {
        return _getLiquidityForAmounts(amount0, amount1);
    }

    function getAmountsForLiquidity(uint128 liquidity) public view returns (uint256 amount0, uint256 amount1) {
        return _getAmountsForLiquidity(liquidity);
    }

    function getUsableLiquidityFromYieldSources() public view returns (uint256) {
        return _getUsableLiquidityFromYieldSources();
    }

    function getAmountInYieldSource(Currency currency) public view returns (uint256) {
        return _getAmountInYieldSource(currency);
    }

    // Exclude from coverage report
    function test() public {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title AbstractAssetVault
 * @dev ERC-4626-inspired minimal vault for abstract assets that don't have an address of their own,
 * such as Uniswap V3/V4 liquidity units, staking derivatives, or computed values.
 *
 * Unlike ERC-4626, this vault doesn't require an `asset()` function. Instead, implementers define
 * `totalAssets()` to return the current amount of the abstract asset.
 *
 * Implementers MUST:
 * - Override `totalAssets()` to return the current total of the abstract asset
 * - Implement deposit/withdrawal logic in their own functions
 * - Handle actual asset management (e.g., Uniswap positions, staking)
 *
 * Example:
 * ```solidity
 * function totalAssets() public view override returns (uint256) {
 *     return _getLiquidity();
 * }
 *
 * function addLiquidity(uint256 liquidity) external {
 *     if liquidity > maxDeposit(msg.sender) {
 *         revert AbstractVaultExceededMaxDeposit(msg.sender, liquidity, maxDeposit(msg.sender));
 *     }
 *     uint256 shares = previewDeposit(liquidity);
 *     _addLiquidity(liquidity);
 *     _mint(msg.sender, shares);
 * }
 *
 * function removeLiquidity(uint256 liquidity) external {
 *     uint256 shares = previewWithdraw(liquidity);
 *     _burn(msg.sender, shares);
 *     _removeLiquidity(liquidity);
 * }
 * ```
 *
 * NOTE: Includes inflation attack protection via virtual shares/assets. For more info, see:
 * https://docs.openzeppelin.com/contracts/5.x/erc4626#inflation-attack
 *
 * WARNING: This is experimental software and is provided on an "as is" and "as available" basis.
 * We do not give any warranties and will not be liable for any losses incurred through any use of
 * this code base.
 * _Available since v1.1.0_
 */
abstract contract AbstractAssetVault is ERC20 {
    using Math for uint256;

    /**
     * @dev Attempted to deposit more assets than the max amount for `receiver`.
     */
    error AbstractAssetVaultExceededMaxDeposit(address receiver, uint256 assets, uint256 max);

    /**
     * @dev Attempted to mint more shares than the max amount for `receiver`.
     */
    error AbstractAssetVaultExceededMaxMint(address receiver, uint256 shares, uint256 max);

    /**
     * @dev Attempted to withdraw more assets than the max amount for `receiver`.
     */
    error AbstractAssetVaultExceededMaxWithdraw(address owner, uint256 assets, uint256 max);

    /**
     * @dev Attempted to redeem more shares than the max amount for `receiver`.
     */
    error AbstractAssetVaultExceededMaxRedeem(address owner, uint256 shares, uint256 max);

    /**
     * @dev Returns the current total of the abstract asset.
     */
    function totalAssets() public view virtual returns (uint256);

    /**
     * @dev See {IERC4626-convertToShares}.
     */
    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /**
     * @dev See {IERC4626-convertToAssets}.
     */
    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /**
     * @dev See {IERC4626-maxDeposit}.
     */
    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev See {IERC4626-maxMint}.
     */
    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev See {IERC4626-maxWithdraw}.
     */
    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
    }

    /**
     * @dev See {IERC4626-maxRedeem}.
     */
    function maxRedeem(address owner) public view virtual returns (uint256) {
        return balanceOf(owner);
    }

    /**
     * @dev See {IERC4626-previewDeposit}.
     */
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /**
     * @dev See {IERC4626-previewMint}.
     */
    function previewMint(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

    /**
     * @dev See {IERC4626-previewWithdraw}.
     */
    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    /**
     * @dev See {IERC4626-previewRedeem}.
     */
    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual returns (uint256) {
        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }

    function _decimalsOffset() internal view virtual returns (uint8) {
        return 0;
    }
}

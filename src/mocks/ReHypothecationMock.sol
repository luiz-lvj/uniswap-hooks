// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReHypothecationHook} from "src/general/ReHypothecationHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

contract ReHypothecationMock is ReHypothecationHook {
    address private _yieldSource0;
    address private _yieldSource1;

    constructor(IPoolManager poolManager_) ReHypothecationHook(poolManager_) ERC20("ReHypothecationMock", "RHM") {}

    function setYieldSources(address yieldSource0_, address yieldSource1_) external {
        _yieldSource0 = yieldSource0_;
        _yieldSource1 = yieldSource1_;
    }

    // overrides for testing
    function getYieldSourceForCurrency(Currency currency) public view override returns (address) {
        PoolKey memory poolKey = getPoolKey();
        if (currency == poolKey.currency0) {
            return _yieldSource0;
        }
        if (currency == poolKey.currency1) {
            return _yieldSource1;
        }
        revert InvalidCurrency();
    }

    // Exclude from coverage report
    function test() public {}
}

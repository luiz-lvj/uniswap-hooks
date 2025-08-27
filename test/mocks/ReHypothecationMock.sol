// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "src/general/ReHypothecationHook.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

contract ReHypothecationMock is ReHypothecationHook {
    address public yieldSource0;
    address public yieldSource1;

    constructor(IPoolManager _poolManager, address _yieldSource0, address _yieldSource1)
        ReHypothecationHook()
        BaseHook(_poolManager)
        ERC20("ReHypothecationMock", "RHM")
    {
        yieldSource0 = _yieldSource0;
        yieldSource1 = _yieldSource1;
    }

    function setYieldSources(address _yieldSource0, address _yieldSource1) external {
        yieldSource0 = _yieldSource0;
        yieldSource1 = _yieldSource1;
    }

    // overrides for testing
    function getYieldSourceForCurrency(Currency currency) internal view override returns (address) {
        if (currency == poolKey.currency0) {
            return yieldSource0;
        }
        if (currency == poolKey.currency1) {
            return yieldSource1;
        }
        revert InvalidCurrency();
    }
}

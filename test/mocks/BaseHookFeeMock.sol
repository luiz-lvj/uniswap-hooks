// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "src/fee/BaseHookFee.sol";

contract BaseHookFeeMock is BaseHookFee {
    uint256 public immutable fee;

    constructor(IPoolManager _poolManager, uint256 _fee) BaseHookFee(_poolManager) {
        fee = _fee;
    }

    function _getHookFee(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal view override returns (uint256) {
        return fee;
    }

    // Exclude from coverage report
    function test() public {}
}

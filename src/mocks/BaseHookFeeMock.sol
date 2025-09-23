// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHookFee} from "../fee/BaseHookFee.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

contract BaseHookFeeMock is BaseHookFee {
    uint256 public immutable fee;
    address private _feeRecipient;

    constructor(IPoolManager _poolManager, uint256 _fee) BaseHookFee(_poolManager) {
        fee = _fee;
        _feeRecipient = msg.sender;
    }

    function _getHookFee(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        view
        override
        returns (uint256)
    {
        return fee;
    }

    function withdrawFees(Currency[] calldata currencies) public override {
        for (uint256 i = 0; i < currencies.length; i++) {
            currencies[i].transfer(_feeRecipient, currencies[i].balanceOfSelf());
        }
    }

    // Exclude from coverage report
    function test() public {}
}

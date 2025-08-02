// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./contracts/Ownable.sol";
import {Hooks} from "./libraries/Hooks.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {BalanceDelta} from "./types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "./types/BeforeSwapDelta.sol";
import {BaseHook} from "./contracts/BaseHook.sol";

interface IManager {
    function rebalance() external;
    function outOfRange() external view returns(bool);
}

contract AutomatizationHook is Ownable, BaseHook {
    address payable target;
    IManager manager;

    constructor(address _admin) Ownable(_admin) {}

    function changeTarget(address _target) public onlyOwner {
        target = payable(_target);
    }

    function changeManager(address _manager) public onlyOwner {
        manager = IManager(_manager);
    }

    function getHookPermissions()
        internal
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function beforeSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        (bool success, ) = target.call{value: 0}("");
        require(success);
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external virtual override returns (bytes4, int128) {
        if (manager.outOfRange()) {
            manager.rebalance();
        }
        return (this.afterSwap.selector, 0);
    }
}

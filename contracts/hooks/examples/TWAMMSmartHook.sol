// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {TWAMM, PoolKey, IPoolManager} from "./TWAMM.sol";
import {EntryPoint} from "../../smarthook/EntryPoint.sol";
import {BaseSmartHook, IExternalHook} from "../../smarthook/BaseSmartHook.sol";

contract TWAMMSmartHook is TWAMM, BaseSmartHook {
    constructor(
        IPoolManager poolManager,
        uint256 interval,
        EntryPoint _entryPoint,
        IExternalHook.Trigger[] memory _triggers,
        address _hook
    ) TWAMM(poolManager, interval) BaseSmartHook(_entryPoint, _triggers, _hook) {}

    PoolKey[] allKeys;

    function getPoolKey(uint256 i) external view returns (PoolKey memory pkey) {
        return allKeys[i];
    }

    function beforeInitialize(address, PoolKey calldata key, uint160, bytes calldata)
        external
        virtual
        override
        poolManagerOnly
        returns (bytes4)
    {
        initialize(_getTWAMM(key));
        allKeys.push(key);
        return this.beforeInitialize.selector;
    }

    event ExecuteOps_TWAMMOrders(PoolKey pkey, Trigger trigger);

    function executeOps(Trigger trigger) external override returns (bool) {
        /*         if (_validateOps(trigger) == false) {
            return false;
        } */
        for (uint256 i = 0; i < allKeys.length; i++) {
            executeTWAMMOrders(allKeys[i]);
            emit ExecuteOps_TWAMMOrders(allKeys[i], trigger);
        }
        return true;
    }
}

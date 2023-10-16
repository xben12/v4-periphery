// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {BaseHook} from "../../../contracts/BaseHook.sol";
import {TWAMMSmartHook} from "../../../contracts/hooks/examples/TWAMMSmartHook.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";

import {EntryPoint, IExternalHook} from "../../../contracts/smarthook/EntryPoint.sol";

contract TWAMMSmartHookImpl is TWAMMSmartHook {
    constructor(
        IPoolManager poolManager,
        uint256 interval,
        EntryPoint _entryPoint,
        IExternalHook.Trigger[] memory _triggers,
        TWAMMSmartHook addressToEtch
    ) TWAMMSmartHook(poolManager, interval, _entryPoint, _triggers, address(addressToEtch)) {
        Hooks.validateHookAddress(addressToEtch, getHooksCalls());
    }

    /*     constructor(IPoolManager poolManager, uint256 interval, TWAMM addressToEtch) TWAMM(poolManager, interval) {
        Hooks.validateHookAddress(addressToEtch, getHooksCalls());
    } */

    // make this a no-op in testing
    function validateHookAddress(BaseHook _this) internal pure override {}
}

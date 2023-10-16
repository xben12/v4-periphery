//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IExternalHook} from "./IExternalHook.sol";
import {EntryPoint} from "./EntryPoint.sol";

contract BaseSmartHook is IExternalHook {
    EntryPoint entryPoint;
    mapping(IExternalHook.Trigger => bool) mapTriggers;

    constructor(EntryPoint _entryPoint, IExternalHook.Trigger[] memory _triggers, address _hook) {
        entryPoint = _entryPoint;
        for (uint256 i = 0; i < _triggers.length; i++) {
            mapTriggers[_triggers[i]] = true;
        }
        entryPoint.register(_triggers, _hook);
    }

    function _validateOps(Trigger trigger) internal view returns (bool) {
        return mapTriggers[trigger];
    }

    function validateOps(Trigger trigger) external view virtual returns (bool) {
        return _validateOps(trigger);
    }

    function executeOps(Trigger trigger) external virtual returns (bool) {
        if (mapTriggers[trigger] == false) {
            return false;
        }
        return true;
    }
}

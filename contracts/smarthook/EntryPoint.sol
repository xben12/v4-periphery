//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IExternalHook} from "./IExternalHook.sol";
import "./BaseSmartHook.sol";

contract EntryPoint {
    error WithdrawalAmountLargerThanBalance();

    uint256 constant MIN_DEPOSIT_ETHER = 0.1 ether;

    mapping(address => uint256) balance;
    mapping(IExternalHook.Trigger => mapping(address => bool)) registry;
    mapping(IExternalHook.Trigger => address[]) registered_addr;
    mapping(address => bool) eoaCallers;

    /*     modifier EOACallerOnly() {
        require(eoaCallers[msg.sender] == true, "Only Registered EOA can trigger!");
        _;
    } */

    function register(IExternalHook.Trigger[] calldata triggers, address hook) public {
        if (hook == address(0)) {
            hook = msg.sender;
        }
        for (uint256 i = 0; i < triggers.length; i++) {
            if (registry[triggers[i]][hook] == false) {
                registry[triggers[i]][hook] = true;
            }
            _addIntoRegisteredAddr(triggers[i], hook);
        }
    }

    function _findAddressIndex(IExternalHook.Trigger trigger, address addr)
        internal
        view
        returns (bool found, uint256 position)
    {
        for (position = 0; position < registered_addr[trigger].length; position++) {
            if (registered_addr[trigger][position] == addr) {
                found = true;
                break;
            }
        }
    }

    function _addIntoRegisteredAddr(IExternalHook.Trigger trigger, address addr) internal {
        (bool found,) = _findAddressIndex(trigger, addr);
        if (found == false) {
            registered_addr[trigger].push(addr);
        }
    }

    function _removeRegisteredAddr(IExternalHook.Trigger trigger, address addr) internal {
        (bool found, uint256 position) = _findAddressIndex(trigger, addr);
        if (found == true) {
            registered_addr[trigger][position] = address(0);
        }
    }

    function deregister(IExternalHook.Trigger[] calldata triggers) public {
        for (uint256 i = 0; i < triggers.length; i++) {
            if (registry[triggers[i]][msg.sender] == true) {
                registry[triggers[i]][msg.sender] = false;
            }
            _removeRegisteredAddr(triggers[i], msg.sender);
        }
    }

    //smarthook contract will call this function. only smarthook with deposit can be triggered.
    function deposit(IExternalHook.Trigger[] calldata triggers, address hook) public payable {
        require(msg.value > MIN_DEPOSIT_ETHER, "minimum depsoit required!");
        if (hook == address(0)) {
            hook = msg.sender;
        }
        balance[hook] = msg.value;
        if (triggers.length > 0) {
            register(triggers, hook);
        }
    }

    // amount = 0 : withdraw everything
    function withdrawal(uint256 amount) public returns (bool success) {
        if (amount == 0) {
            amount = balance[msg.sender];
        } else {
            if (amount > balance[msg.sender]) {
                revert WithdrawalAmountLargerThanBalance();
            }
        }

        balance[msg.sender] = balance[msg.sender] - amount;
        (success,) = msg.sender.call{value: amount}("");
    }

    function handleOps(IExternalHook.Trigger trigger) public returns (bool bexecuted) {
        address[] storage registered_hook = registered_addr[trigger];
        for (uint256 i = 0; i < registered_hook.length; i++) {
            if (registry[trigger][registered_hook[i]]) {
                IExternalHook(registered_hook[i]).executeOps(trigger);
                bexecuted = true;
            }
        }
        return bexecuted;
    }
}

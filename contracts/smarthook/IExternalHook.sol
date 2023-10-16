//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IExternalHook {
    enum Trigger {
        TIME_INTERVAL_100S,
        TIME_INTERVAL_1000S,
        TIME_INTERVAL_10000S
    }

    function validateOps(Trigger tigger) external returns (bool);
    function executeOps(Trigger tigger) external returns (bool);
}

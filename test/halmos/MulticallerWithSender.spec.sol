// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

contract MulticallerWithSenderSpec {
    error ArrayLengthsMismatch();

    error Reentrancy();

    address public sender;
    bool public reentrancyUnlocked;

    constructor() payable {
        reentrancyUnlocked = true;
    }

    function aggregateWithSender(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external payable returns (bytes[] memory) {
        if (targets.length != data.length || data.length != values.length) {
            revert ArrayLengthsMismatch();
        }

        if (!reentrancyUnlocked) {
            revert Reentrancy();
        }

        bytes[] memory results = new bytes[](data.length);

        if (data.length == 0) {
            return results;
        }

        // Lock
        sender = msg.sender;
        reentrancyUnlocked = false;

        for (uint i = 0; i < data.length; i++) {
            (bool success, bytes memory retdata) = targets[i].call{value: values[i]}(data[i]);
            if (!success) {
                _revertWithReturnData();
            }
            results[i] = retdata;
        }

        // Unlock
        sender = address(0);
        reentrancyUnlocked = true;

        return results;
    }

    function _revertWithReturnData() internal pure {
        assembly {
            returndatacopy(0, 0, returndatasize())
            revert(0, returndatasize())
        }
    }
}

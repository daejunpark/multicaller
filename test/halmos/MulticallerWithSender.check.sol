// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {MulticallerWithSender} from "../../src/MulticallerWithSender.sol";
import {MulticallerWithSenderSpec} from "./MulticallerWithSender.spec.sol";

import "forge-std/Test.sol";
import {SymTest} from "halmos-cheatcodes/SymTest.sol";

contract MulticallerWithSenderMock is MulticallerWithSender {
    // Provide public getters for the storage variables.
    // Note: the variable order is set to align with the packing scheme used by the implementation.
    address public sender;
    bool public reentrancyUnlocked;
}

// A mock target contract that keeps track of external calls made via Multicaller
contract TargetMock is SymTest {
    // Flag to whether the call to this is expected to succeed or not.
    bool private success;

    // Record of values received from each caller.
    mapping (address => uint) private balanceOf;

    constructor() {
        success = svm.createBool("success");
    }

    fallback(bytes calldata data) external payable returns (bytes memory) {
        balanceOf[msg.sender] += msg.value;

        if (success) {
            // Return the callvalue and calldata, which can then be retrieved later when checking the results of multicalls.
            return abi.encode(msg.value, data);
        } else {
            revert();
        }
    }
}

// Check equivalence between the implementation and the reference spec.
// Establishing equivalence ensures that no mistakes are made in the optimizations made by the implementation.
contract MulticallerWithSenderSymTest is SymTest, Test {
    MulticallerWithSenderMock impl; // implementation
    MulticallerWithSenderSpec spec; // reference spec

    // Slot number of the `balanceOf` mapping in TargetMock.
    uint private constant _BALANCEOF_SLOT = 1;

    function setUp() public {
        impl = new MulticallerWithSenderMock();
        spec = new MulticallerWithSenderSpec();

        assert(impl.sender() == spec.sender());
        assert(impl.reentrancyUnlocked() == spec.reentrancyUnlocked());

        vm.deal(address(this), 100_000_000 ether);
        vm.assume(address(impl).balance == address(spec).balance);
    }

    function _check_equivalence(
        address[] memory targets,
        bytes[] memory data,
        uint256[] memory values
    ) internal {
        uint value = svm.createUint256("value");

        (bool success_impl, bytes memory retdata_impl) =
            address(impl).call{value: value}(abi.encodeWithSelector(impl.aggregateWithSender.selector, targets, data, values));
        (bool success_spec, bytes memory retdata_spec) =
            address(spec).call{value: value}(abi.encodeWithSelector(spec.aggregateWithSender.selector, targets, data, values));

        // Check: `impl` succeeds if and only if `spec` succeeds.
        assert(success_impl == success_spec);
        // Check: the return data must be identical.
        assert(keccak256(retdata_impl) == keccak256(retdata_spec));

        // Check: the storage states must remain the same.
        assert(impl.sender() == spec.sender());
        assert(impl.reentrancyUnlocked() == spec.reentrancyUnlocked());

        // Check: the remaining balances must be equal.
        assert(address(impl).balance == address(spec).balance);
        // Check: the total amounts sent to each target must be equal.
        for (uint i = 0; i < targets.length; i++) {
            bytes32 target_balance_impl = vm.load(targets[i], keccak256(abi.encode(impl, _BALANCEOF_SLOT)));
            bytes32 target_balance_spec = vm.load(targets[i], keccak256(abi.encode(spec, _BALANCEOF_SLOT)));
            assert(target_balance_impl == target_balance_spec);
        }
    }

    // Generate input arguments for `aggregateWithSender()`, given the specific sizes of dynamic arrays.
    function _create_inputs(
        uint targets_length,
        uint data_length,
        uint values_length,
        uint data_size
    ) internal returns (
        address[] memory targets,
        bytes[] memory data,
        uint256[] memory values
    ) {
        // Construct `address[] targets` where `target[i]` may or may not be aliased with `target[i-1]`.
        // This results in 2^(n-1) combinations of `targets` arrays, covering various alias scenarios.
        targets = new address[](targets_length);
        for (uint i = 0; i < targets_length; i++) {
            if (i == 0 || svm.createBool("unique_targets[i]")) {
                targets[i] = address(new TargetMock());
            } else {
                targets[i] = targets[i-1]; // alias
            }
        }

        // Construct `bytes[] data`, where `bytes data[i]` is created with the given `data_size`.
        data = new bytes[](data_length);
        for (uint i = 0; i < data_length; i++) {
            data[i] = svm.createBytes(data_size, "data[i]");
        }

        // Construct `uint256[] values`.
        values = new uint256[](values_length);
        for (uint i = 0; i < values_length; i++) {
            values[i] = svm.createUint256("values[i]");
        }
    }

    //
    // Instantiations of the `_check_equivalence()` test for various combinations of dynamic array sizes.
    //

    function check_1_0_0_1() public {
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = _create_inputs(1, 0, 0, 1);
        _check_equivalence(targets, data, values);
    }

    function check_0_0_0_1() public {
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = _create_inputs(0, 0, 0, 1);
        _check_equivalence(targets, data, values);
    }

    function check_1_1_1_1() public {
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = _create_inputs(1, 1, 1, 1);
        _check_equivalence(targets, data, values);
    }

    function check_2_2_2_1() public {
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = _create_inputs(2, 2, 2, 1);
        _check_equivalence(targets, data, values);
    }

    function check_1_0_0_32() public {
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = _create_inputs(1, 0, 0, 32);
        _check_equivalence(targets, data, values);
    }

    function check_0_0_0_32() public {
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = _create_inputs(0, 0, 0, 32);
        _check_equivalence(targets, data, values);
    }

    function check_1_1_1_32() public {
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = _create_inputs(1, 1, 1, 32);
        _check_equivalence(targets, data, values);
    }

    function check_2_2_2_32() public {
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = _create_inputs(2, 2, 2, 32);
        _check_equivalence(targets, data, values);
    }

    function check_1_0_0_31() public {
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = _create_inputs(1, 0, 0, 31);
        _check_equivalence(targets, data, values);
    }

    function check_0_0_0_31() public {
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = _create_inputs(0, 0, 0, 31);
        _check_equivalence(targets, data, values);
    }

    function check_1_1_1_31() public {
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = _create_inputs(1, 1, 1, 31);
        _check_equivalence(targets, data, values);
    }

    function check_2_2_2_31() public {
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = _create_inputs(2, 2, 2, 31);
        _check_equivalence(targets, data, values);
    }

    function check_1_0_0_65() public {
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = _create_inputs(1, 0, 0, 65);
        _check_equivalence(targets, data, values);
    }

    function check_0_0_0_65() public {
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = _create_inputs(0, 0, 0, 65);
        _check_equivalence(targets, data, values);
    }

    function check_1_1_1_65() public {
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = _create_inputs(1, 1, 1, 65);
        _check_equivalence(targets, data, values);
    }

    function check_2_2_2_65() public {
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = _create_inputs(2, 2, 2, 65);
        _check_equivalence(targets, data, values);
    }
}

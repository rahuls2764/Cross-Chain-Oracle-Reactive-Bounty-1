// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library AccessControl {
    struct Roles {
        address owner;
    }

    event OwnershipTransferred(address indexed previous, address indexed current);

    error Unauthorized();
    error InvalidAddress();

    function initialize(Roles storage self, address initialOwner) internal {
        require(initialOwner != address(0), "Invalid owner");
        self.owner = initialOwner;
    }

    function requireOwner(Roles storage self, address caller) internal view {
        if (caller != self.owner) revert Unauthorized();
    }

    function transferOwnership(Roles storage self, address newOwner) internal {
        if (newOwner == address(0)) revert InvalidAddress();
        address previous = self.owner;
        self.owner = newOwner;
        emit OwnershipTransferred(previous, newOwner);
    }
}
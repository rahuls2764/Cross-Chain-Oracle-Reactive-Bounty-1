// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library FeedMetadata {
    struct Metadata {
        address sourceAggregator;
        uint64 sourceChainId;
        uint8 decimals;
        string description;
        bool initialized;
    }

    error AlreadyInitialized();
    error NotInitialized();

    function initialize(
        Metadata storage self,
        address sourceAggregator,
        uint64 sourceChainId,
        uint8 decimals,
        string memory description
    ) internal {
        if (self.initialized) revert AlreadyInitialized();
        require(sourceAggregator != address(0), "Invalid aggregator");
        require(bytes(description).length > 0, "Empty description");

        self.sourceAggregator = sourceAggregator;
        self.sourceChainId = sourceChainId;
        self.decimals = decimals;
        self.description = description;
        self.initialized = true;
    }

    function requireInitialized(Metadata storage self) internal view {
        if (!self.initialized) revert NotInitialized();
    }

    function getDecimals(Metadata storage self) internal view returns (uint8) {
        requireInitialized(self);
        return self.decimals;
    }

    function getDescription(Metadata storage self) internal view returns (string memory) {
        requireInitialized(self);
        return self.description;
    }

    function getSourceInfo(Metadata storage self) 
        internal 
        view 
        returns (address aggregator, uint64 chainId) 
    {
        requireInitialized(self);
        return (self.sourceAggregator, self.sourceChainId);
    }
}
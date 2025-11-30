// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library FeedRegistry {
    struct Feed {
        address aggregator;
        uint64 destinationChainId;
        address destinationFeed;
        string identifier;
        bool active;
        uint256 registeredAt;
    }

    struct Registry {
        mapping(bytes32 => Feed) feeds;
        bytes32[] feedIds;
        mapping(address => bytes32[]) aggregatorToFeeds;
    }

    event FeedRegistered(
        bytes32 indexed feedId,
        address indexed aggregator,
        uint64 destinationChainId,
        address destinationFeed,
        string identifier
    );

    event FeedStatusChanged(bytes32 indexed feedId, bool active);

    function generateFeedId(
        address aggregator,
        uint64 destinationChainId,
        address destinationFeed
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(aggregator, destinationChainId, destinationFeed));
    }

    function register(
        Registry storage self,
        address aggregator,
        uint64 destinationChainId,
        address destinationFeed,
        string memory identifier
    ) internal returns (bytes32 feedId) {
        require(aggregator != address(0), "Invalid aggregator");
        require(destinationFeed != address(0), "Invalid proxy");
        require(bytes(identifier).length > 0, "Empty identifier");

        feedId = generateFeedId(aggregator, destinationChainId, destinationFeed);
        require(self.feeds[feedId].aggregator == address(0), "Feed exists");

        self.feeds[feedId] = Feed({
            aggregator: aggregator,
            destinationChainId: destinationChainId,
            destinationFeed: destinationFeed,
            identifier: identifier,
            active: true,
            registeredAt: block.timestamp
        });

        self.feedIds.push(feedId);
        self.aggregatorToFeeds[aggregator].push(feedId);

        emit FeedRegistered(feedId, aggregator, destinationChainId, destinationFeed, identifier);
    }

    function setActive(Registry storage self, bytes32 feedId, bool active) internal {
        require(self.feeds[feedId].aggregator != address(0), "Feed not found");
        self.feeds[feedId].active = active;
        emit FeedStatusChanged(feedId, active);
    }

    function get(Registry storage self, bytes32 feedId) internal view returns (Feed memory) {
        return self.feeds[feedId];
    }

    function isActive(Registry storage self, bytes32 feedId) internal view returns (bool) {
        return self.feeds[feedId].active;
    }

    function getAllFeedIds(Registry storage self) internal view returns (bytes32[] memory) {
        return self.feedIds;
    }

    function getActiveFeedIds(Registry storage self) internal view returns (bytes32[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < self.feedIds.length; i++) {
            if (self.feeds[self.feedIds[i]].active) activeCount++;
        }

        bytes32[] memory active = new bytes32[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < self.feedIds.length; i++) {
            if (self.feeds[self.feedIds[i]].active) {
                active[index++] = self.feedIds[i];
            }
        }
        return active;
    }

    function getFeedsByAggregator(Registry storage self, address aggregator) 
        internal 
        view 
        returns (bytes32[] memory) 
    {
        return self.aggregatorToFeeds[aggregator];
    }
}